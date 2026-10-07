#ifndef HEDGEDRIFT_RISK_ENGINE_MQH
#define HEDGEDRIFT_RISK_ENGINE_MQH

#include "RuntimeState.mqh"
#include "AccountingEngine.mqh"
#include "TradeEngine.mqh"

struct HD_RiskItem
{
   ulong identifier;
   double initial_sl;
   bool hard_sl;
};

class CHDRiskEngine
{
private:
   HD_RiskItem m_items[];
   double m_initial_risk;
   bool m_ready;
   bool m_closing;
   datetime m_last_close_attempt;

   bool OwnedSelected()
   {
      return PositionGetString(POSITION_SYMBOL) == _Symbol &&
             (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber;
   }

public:
   void Init()
   {
      ArrayResize(m_items, 0);
      m_initial_risk = 0.0;
      m_ready = false;
      m_closing = false;
      m_last_close_attempt = 0;
   }

   double InitialRisk()
   {
      return m_initial_risk;
   }

   double TargetMoney()
   {
      return m_initial_risk * InpRRTargetPercent / 100.0;
   }

   bool BeginBasket()
   {
      ArrayResize(m_items, 0);
      m_initial_risk = 0.0;
      m_ready = false;
      m_closing = false;
      m_last_close_attempt = 0;

      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      int count = 0;

      if(point <= 0.0)
         return false;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionGetTicket(i) == 0 || !OwnedSelected())
            continue;

         ENUM_POSITION_TYPE type =
            (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

         double open = PositionGetDouble(POSITION_PRICE_OPEN);
         double volume = PositionGetDouble(POSITION_VOLUME);
         double sl = PositionGetDouble(POSITION_SL);

         if(g_hd.hard_cut_loss && sl <= 0.0)
         {
            Print("[HedgeDrift][ERROR] Basket has an unprotected position.");
            return false;
         }

         // With Hard SL disabled, RR uses the configured reference distance.
         double risk_price = sl;

         if(!g_hd.hard_cut_loss)
         {
            if(type == POSITION_TYPE_BUY)
               risk_price = open - InpCutLossPoints * point;
            else
               risk_price = open + InpCutLossPoints * point;
         }

         if(risk_price <= 0.0)
            return false;

         if(g_hd.rr_target)
         {
            double pnl = 0.0;
            ENUM_ORDER_TYPE order_type =
               type == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

            if(!OrderCalcProfit(order_type, _Symbol, volume,
                                open, risk_price, pnl) ||
               pnl >= 0.0)
            {
               Print("[HedgeDrift][ERROR] Initial risk calculation failed.");
               return false;
            }

            m_initial_risk += -pnl;
         }

         int index = ArraySize(m_items);
         if(ArrayResize(m_items, index + 1) != index + 1)
            return false;

         m_items[index].identifier =
            (ulong)PositionGetInteger(POSITION_IDENTIFIER);

         m_items[index].initial_sl = sl;
         m_items[index].hard_sl = g_hd.hard_cut_loss && sl > 0.0;
         count++;
      }

      if(count == 0)
         return false;

      if(g_hd.rr_target && m_initial_risk <= 0.0)
         return false;

      m_ready = true;

      Print("[HedgeDrift][INFO] Basket risk locked. InitialRisk=",
            DoubleToString(m_initial_risk, 2),
            " Target=", DoubleToString(TargetMoney(), 2),
            " Currency=", AccountInfoString(ACCOUNT_CURRENCY));

      return true;
   }

   bool HardCutPrice(const ulong deal, double &close_price)
   {
      close_price = 0.0;

      if(!HistoryDealSelect(deal))
         return false;

      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
         return false;

      ENUM_DEAL_ENTRY entry =
         (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);

      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
         return false;

      if((ENUM_DEAL_REASON)HistoryDealGetInteger(deal, DEAL_REASON)
         != DEAL_REASON_SL)
         return false;

      ulong identifier =
         (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);

      double deal_sl = HistoryDealGetDouble(deal, DEAL_SL);
      double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

      if(tick_size <= 0.0)
         return false;

      for(int i = 0; i < ArraySize(m_items); i++)
      {
         if(m_items[i].identifier != identifier ||
            !m_items[i].hard_sl)
            continue;

         // A moved BE/trailing SL is not the original Hard SL.
         if(MathAbs(deal_sl - m_items[i].initial_sl) > tick_size * 0.5)
            return false;

         close_price = HistoryDealGetDouble(deal, DEAL_PRICE);
         return close_price > 0.0;
      }

      return false;
   }

   bool Tick(CHDTradeEngine &trade, CHDAccounting &accounting)
   {
      if(trade.Count() == 0)
         return false;

      if(!m_ready)
      {
         Print("[HedgeDrift][ERROR] Active basket without risk snapshot.");
         m_closing = true;
      }

      accounting.RefreshFloating();

      if(m_ready && g_hd.rr_target &&
         m_initial_risk > 0.0 &&
         accounting.Floating() >= TargetMoney())
      {
         if(!m_closing)
         {
            Print("[HedgeDrift][INFO] Basket RR reached. OR=",
                  DoubleToString(accounting.Floating(), 2),
                  " Target=", DoubleToString(TargetMoney(), 2));
         }

         m_closing = true;
      }

      if(m_closing)
      {
         // Retry remaining positions at most once per server second.
         if(m_last_close_attempt != TimeCurrent())
         {
            m_last_close_attempt = TimeCurrent();
            HD_SetCycle(HD_CLOSING);
            trade.CloseAll();
         }

         return true;
      }

      if(!g_hd.auto_be)
         return false;

      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

      if(point <= 0.0 || tick_size <= 0.0)
         return false;

      MqlTick tick;
      if(!SymbolInfoTick(_Symbol, tick))
         return false;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !OwnedSelected())
            continue;

         ENUM_POSITION_TYPE type =
            (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

         bool buy = type == POSITION_TYPE_BUY;
         double open = PositionGetDouble(POSITION_PRICE_OPEN);
         double current_sl = PositionGetDouble(POSITION_SL);

         double profit_points =
            buy ? (tick.bid - open) / point
                : (open - tick.ask) / point;

         if(profit_points < InpBETriggerPoints)
            continue;

         double basis = InpBETriggerPoints;

         if(g_hd.be_type == BE_TYPE_DYNAMIC)
         {
            basis += 10.0 *
               MathFloor((profit_points - InpBETriggerPoints) / 10.0);
         }

         double lock_points = basis * InpBELockPercent / 100.0;
         double candidate =
            buy ? open + lock_points * point
                : open - lock_points * point;

         // Round toward the open price, not toward the market.
         candidate = buy
            ? MathFloor(candidate / tick_size + 1e-9) * tick_size
            : MathCeil(candidate / tick_size - 1e-9) * tick_size;

         candidate = NormalizeDouble(candidate, _Digits);

         if(buy && candidate <= open)
            continue;

         if(!buy && candidate >= open)
            continue;

         if(current_sl > 0.0)
         {
            if(buy && candidate <= current_sl + tick_size * 0.5)
               continue;

            if(!buy && candidate >= current_sl - tick_size * 0.5)
               continue;
         }

         trade.ModifyStop(ticket, candidate);
      }

      return false;
   }
};

#endif