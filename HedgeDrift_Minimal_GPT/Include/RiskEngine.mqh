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

   ENUM_POSITION_TYPE side;
   bool side_known;
   double best_price;
   bool peak_ready;
   bool trail_pending;
};

class CHDRiskEngine
{
private:
   HD_RiskItem m_items[];
   double m_initial_risk;
   bool m_ready;
   bool m_closing;
   datetime m_last_close_attempt;
   datetime m_last_trail_attempt;
   bool m_peak_dirty;

   bool IdentifierLive(const ulong identifier)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionGetTicket(i) == 0 || !OwnedSelected())
            continue;

         if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == identifier)
            return true;
      }

      return false;
   }

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
      m_last_trail_attempt = 0;
      m_peak_dirty = false;
   }

   void RequestClose()
   {
      m_closing = true;
      m_last_close_attempt = 0;
   }

   bool Closing()
   {
      return m_closing;
   }

   void SaveState(CHDPersistence &state)
   {
      state.PutD("risk_initial", m_initial_risk);
      state.PutU("risk_ready", (ulong)m_ready);
      state.PutU("risk_closing", (ulong)m_closing);
      state.PutU("risk_count", (ulong)ArraySize(m_items));
      state.PutU("trail_version", 1);

      for(int i = 0; i < ArraySize(m_items); i++)
      {
         string key = "risk_" + IntegerToString(i);

         state.PutU(key + "_id", m_items[i].identifier);
         state.PutD(key + "_sl", m_items[i].initial_sl);
         state.PutU(key + "_hard", (ulong)m_items[i].hard_sl);
         state.PutU(key + "_side", (ulong)m_items[i].side);
         state.PutU(key + "_side_known", (ulong)m_items[i].side_known);
         state.PutD(key + "_peak", m_items[i].best_price);
         state.PutU(key + "_peak_ready", (ulong)m_items[i].peak_ready);
         state.PutU(key + "_trail_pending", (ulong)m_items[i].trail_pending);
      }
   }

   bool LoadState(CHDPersistence &state)
   {
      m_initial_risk = state.D("risk_initial");
      m_ready = state.B("risk_ready");
      m_closing = state.B("risk_closing");

      int count = state.I("risk_count");
      m_last_close_attempt = 0;
      m_last_trail_attempt = 0;
      m_peak_dirty = false;

      bool extended = state.Has("trail_version");

      if(state.Has("feature_version") && !extended)
         return false;

      if(extended && state.I("trail_version") != 1)
         return false;

      if(!state.Good() || m_initial_risk < 0.0 ||
         count > 2 || ArrayResize(m_items, count) != count)
         return false;

      for(int i = 0; i < count; i++)
      {
         string key = "risk_" + IntegerToString(i);

         m_items[i].identifier = state.U(key + "_id");
         m_items[i].initial_sl = state.D(key + "_sl");
         m_items[i].hard_sl = state.B(key + "_hard");

         m_items[i].side = POSITION_TYPE_BUY;
         m_items[i].side_known = false;
         m_items[i].best_price = 0.0;
         m_items[i].peak_ready = false;
         m_items[i].trail_pending = false;

         if(extended)
         {
            int side = state.I(key + "_side");

            if(side > 1)
               return false;

            m_items[i].side = (ENUM_POSITION_TYPE)side;
            m_items[i].side_known = state.B(key + "_side_known");
            m_items[i].best_price = state.D(key + "_peak");
            m_items[i].peak_ready = state.B(key + "_peak_ready");
            m_items[i].trail_pending = state.B(key + "_trail_pending");

            if(m_items[i].best_price < 0.0 ||
               (m_items[i].peak_ready && m_items[i].best_price <= 0.0))
               return false;
         }

         if(m_items[i].identifier == 0 ||
            m_items[i].initial_sl < 0.0)
            return false;

         for(int j = 0; j < i; j++)
         {
            if(m_items[j].identifier == m_items[i].identifier)
               return false;
         }
      }

      return state.Good();
   }

   bool CoversLiveBasket()
   {
      int live = 0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionGetTicket(i) == 0 || !OwnedSelected())
            continue;

         live++;

         ulong identifier =
            (ulong)PositionGetInteger(POSITION_IDENTIFIER);

         bool found = false;

         for(int j = 0; j < ArraySize(m_items); j++)
         {
            if(m_items[j].identifier != identifier)
               continue;

            ENUM_POSITION_TYPE live_side =
               (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

            if(m_items[j].side_known &&
               m_items[j].side != live_side)
               return false;

            if(m_items[j].hard_sl &&
               PositionGetDouble(POSITION_SL) <= 0.0)
               return false;

            found = true;
            break;
         }

         if(!found)
            return false;
      }

      if(live == 0)
         return true;

      return m_ready &&
             (!g_hd.rr_target || m_initial_risk > 0.0);
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
         m_items[index].side = type;
         m_items[index].side_known = true;
         m_items[index].best_price = 0.0;
         m_items[index].peak_ready = false;
         m_items[index].trail_pending = false;
         count++;
      }

      if(count == 0)
         return false;

      if(g_hd.rr_target && m_initial_risk <= 0.0)
         return false;

      m_ready = true;

      if(g_audit.Active())
      {
         g_audit.Record("RISK_LOCKED",
            "{\"initial_risk\":" + g_audit.D(m_initial_risk) +
            ",\"target\":" + g_audit.D(TargetMoney()) +
            ",\"rr_enabled\":" + g_audit.Bool(g_hd.rr_target) +
            ",\"items\":" + IntegerToString(ArraySize(m_items)) + "}");
      }

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

   bool CanReHedge()
   {
      return m_ready && !m_closing;
   }

   bool PeakDirty()
   {
      return m_peak_dirty;
   }

   void MarkSaved()
   {
      m_peak_dirty = false;
   }

   bool RegisterReplacement(const ulong ticket,
                            const double original_sl = 0.0)
   {
      if(!m_ready || !PositionSelectByTicket(ticket) ||
         !OwnedSelected())
         return false;

      ENUM_POSITION_TYPE side =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      ulong identifier =
         (ulong)PositionGetInteger(POSITION_IDENTIFIER);

      double sl = PositionGetDouble(POSITION_SL);

      if(g_hd.hard_cut_loss && sl <= 0.0)
         return false;

      for(int i = 0; i < ArraySize(m_items); i++)
         if(m_items[i].identifier == identifier)
            return true;

      int slot = -1;

      for(int i = 0; i < ArraySize(m_items); i++)
      {
         if(m_items[i].side_known &&
            m_items[i].side == side &&
            !IdentifierLive(m_items[i].identifier))
         {
            slot = i;
            break;
         }
      }

      if(slot < 0)
      {
         for(int i = 0; i < ArraySize(m_items); i++)
         {
            if(!IdentifierLive(m_items[i].identifier))
            {
               slot = i;
               break;
            }
         }
      }

      if(slot < 0)
      {
         int count = ArraySize(m_items);

         if(count >= 2 ||
            ArrayResize(m_items, count + 1) != count + 1)
            return false;

         slot = count;
      }

      double initial_sl = original_sl > 0.0 ? original_sl : sl;

      m_items[slot].identifier = identifier;
      m_items[slot].initial_sl = initial_sl;
      m_items[slot].hard_sl =
         g_hd.hard_cut_loss && initial_sl > 0.0;
      m_items[slot].side = side;
      m_items[slot].side_known = true;
      m_items[slot].best_price = 0.0;
      m_items[slot].peak_ready = false;
      m_items[slot].trail_pending = false;

      m_peak_dirty = true;

      Print("[HedgeDrift][INFO] Replacement registered. Ticket=", ticket,
            " InitialRisk unchanged=", DoubleToString(m_initial_risk, 2));

      return true;
   }

   void UpdateTrailingPeaks()
   {
      if(m_closing)
         return;

      MqlTick tick;

      if(!HD_ReadValidTick(_Symbol, tick))
         return;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionGetTicket(i) == 0 || !OwnedSelected())
            continue;

         ulong identifier =
            (ulong)PositionGetInteger(POSITION_IDENTIFIER);

         ENUM_POSITION_TYPE side =
            (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

         double price = side == POSITION_TYPE_BUY ? tick.bid : tick.ask;

         for(int j = 0; j < ArraySize(m_items); j++)
         {
            if(m_items[j].identifier != identifier)
               continue;

            if(!m_items[j].side_known)
            {
               m_items[j].side = side;
               m_items[j].side_known = true;
               m_peak_dirty = true;
            }

            if(!InpEnableTrailingTP)
            {
               if(m_items[j].trail_pending)
               {
                  m_items[j].trail_pending = false;
                  m_peak_dirty = true;
               }

               break;
            }

            if(!m_items[j].peak_ready)
            {
               m_items[j].best_price = price;
               m_items[j].peak_ready = true;
               m_peak_dirty = true;

               Print("[HedgeDrift][INFO] Trailing peak initialized. ID=",
                     identifier,
                     " Price=", DoubleToString(price, _Digits));
            }
            else if((side == POSITION_TYPE_BUY &&
                     price > m_items[j].best_price) ||
                    (side == POSITION_TYPE_SELL &&
                     price < m_items[j].best_price))
            {
               m_items[j].best_price = price;
               m_peak_dirty = true;
            }

            break;
         }
      }
   }

   bool PrepareTrailing(ulong &tickets[])
   {
      ArrayResize(tickets, 0);

      if(!InpEnableTrailingTP || m_closing)
         return false;

      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      if(point <= 0.0)
         return false;

      MqlTick tick;
      if(!HD_ReadValidTick(_Symbol, tick))
         return false;

      double distance = InpTrailingStepPoints * point;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);

         if(ticket == 0 || !OwnedSelected())
            continue;

         double position_profit = PositionGetDouble(POSITION_PROFIT);

         if(position_profit <= 0.0)
         {
            if(g_audit.Active())
            {
               ulong guard_id =
                  (ulong)PositionGetInteger(POSITION_IDENTIFIER);

               ENUM_POSITION_TYPE guard_side =
                  (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

               bool threshold_reached = false;

               for(int j = 0; j < ArraySize(m_items); j++)
               {
                  if(m_items[j].identifier != guard_id ||
                     !m_items[j].peak_ready)
                     continue;

                  double guard_market =
                     guard_side == POSITION_TYPE_BUY
                     ? tick.bid : tick.ask;

                  double guard_reversal =
                     guard_side == POSITION_TYPE_BUY
                     ? m_items[j].best_price - guard_market
                     : guard_market - m_items[j].best_price;

                  double guard_tolerance = HD_PriceTolerance(
                     m_items[j].best_price, guard_market, point
                  );

                  threshold_reached =
                     guard_reversal + guard_tolerance >= distance;

                  if(threshold_reached &&
                     g_audit.Gate("TRAIL_PROFIT_BLOCK", ticket))
                  {
                     g_audit.Record("TRAIL_PROFIT_BLOCK",
                        "{\"profit\":" + g_audit.D(position_profit) +
                        ",\"peak\":" + g_audit.D(m_items[j].best_price) +
                        ",\"bid\":" + g_audit.D(tick.bid) +
                        ",\"ask\":" + g_audit.D(tick.ask) +
                        ",\"reversal_points\":" +
                        g_audit.D(guard_reversal / point) +
                        ",\"step_points\":" +
                        IntegerToString(InpTrailingStepPoints) + "}",
                        ticket);
                  }

                  break;
               }

               if(!threshold_reached)
                  g_audit.ClearGate("TRAIL_PROFIT_BLOCK", ticket);
            }

            continue;
         }

         if(g_audit.Active())
            g_audit.ClearGate("TRAIL_PROFIT_BLOCK", ticket);

         ulong identifier =
            (ulong)PositionGetInteger(POSITION_IDENTIFIER);

         ENUM_POSITION_TYPE side =
            (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

         for(int j = 0; j < ArraySize(m_items); j++)
         {
            if(m_items[j].identifier != identifier ||
               !m_items[j].peak_ready)
               continue;

            double market =
               side == POSITION_TYPE_BUY ? tick.bid : tick.ask;

            double reversal = side == POSITION_TYPE_BUY
               ? m_items[j].best_price - market
               : market - m_items[j].best_price;

            double tolerance = HD_PriceTolerance(
               m_items[j].best_price, market, point
            );

            if(!m_items[j].trail_pending &&
               reversal + tolerance < distance)
               break;

            if(!m_items[j].trail_pending)
            {
               m_items[j].trail_pending = true;
               m_peak_dirty = true;

               if(g_audit.Active())
               {
                  g_audit.Record("TRAIL_TRIGGER",
                     "{\"identifier\":" +
                     g_audit.U(m_items[j].identifier) +
                     ",\"side\":" + IntegerToString((int)side) +
                     ",\"peak\":" + g_audit.D(m_items[j].best_price) +
                     ",\"bid\":" + g_audit.D(tick.bid) +
                     ",\"ask\":" + g_audit.D(tick.ask) +
                     ",\"profit\":" + g_audit.D(position_profit) +
                     ",\"reversal_points\":" + g_audit.D(reversal / point) +
                     ",\"step_points\":" +
                     IntegerToString(InpTrailingStepPoints) + "}",
                     ticket);
               }

               Print("[HedgeDrift][INFO] Trailing TP triggered. Ticket=",
                     ticket, " ReversalPoints=",
                     DoubleToString(reversal / point, 1));
            }

            int count = ArraySize(tickets);

            if(ArrayResize(tickets, count + 1) != count + 1)
               return false;

            tickets[count] = ticket;
            break;
         }
      }

      return ArraySize(tickets) > 0;
   }

   bool TrailAttemptAllowed()
   {
      if(m_last_trail_attempt == TimeCurrent())
         return false;

      m_last_trail_attempt = TimeCurrent();
      return true;
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
            if(g_audit.Active())
            {
               g_audit.Record("RR_TRIGGER",
                  "{\"or\":" + g_audit.D(accounting.Floating()) +
                  ",\"initial_risk\":" + g_audit.D(m_initial_risk) +
                  ",\"target\":" + g_audit.D(TargetMoney()) + "}");
            }

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
      if(!HD_ReadValidTick(_Symbol, tick))
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

         double market = buy ? tick.bid : tick.ask;

         double profit_points =
            buy ? (market - open) / point
                : (open - market) / point;

         double tolerance_points =
            HD_PriceTolerance(open, market, point) / point;

         if(profit_points + tolerance_points < InpBETriggerPoints)
            continue;

         double basis = InpBETriggerPoints;

         if(g_hd.be_type == BE_TYPE_DYNAMIC)
         {
            double excess_points = MathMax(
               0.0,
               profit_points - InpBETriggerPoints + tolerance_points
            );

            basis += 10.0 * MathFloor(excess_points / 10.0);
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