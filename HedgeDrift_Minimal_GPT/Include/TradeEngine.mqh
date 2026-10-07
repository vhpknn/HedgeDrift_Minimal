#ifndef HEDGEDRIFT_TRADE_ENGINE_MQH
#define HEDGEDRIFT_TRADE_ENGINE_MQH

#include <Trade\Trade.mqh>
#include "Config.mqh"

class CHDTradeEngine
{
private:
   CTrade m_trade;
   string m_symbol;
   ulong  m_magic;
   bool   m_busy;

   bool CheckResult(const bool sent, const string action)
   {
      uint code = m_trade.ResultRetcode();

      bool executed =
         sent &&
         (code == TRADE_RETCODE_DONE ||
          code == TRADE_RETCODE_DONE_PARTIAL);

      Print("[HedgeDrift][", executed ? "INFO" : "ERROR", "] ",
            action,
            " Retcode=", code,
            " ", m_trade.ResultRetcodeDescription());

      return executed;
   }

   bool TradingAllowed()
   {
      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
         !MQLInfoInteger(MQL_TRADE_ALLOWED) ||
         !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) ||
         !AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      {
         Print("[HedgeDrift][ERROR] Trading permission is disabled.");
         return false;
      }

      return true;
   }

   double NormalizeLot(const double requested)
   {
      double minimum = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double maximum = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      double step    = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);

      if(step <= 0.0 || requested < minimum || requested > maximum)
      {
         Print("[HedgeDrift][ERROR] Invalid requested lot: ",
               DoubleToString(requested, 8),
               " Min=", minimum, " Max=", maximum);
         return 0.0;
      }

      double lot =
         NormalizeDouble(MathFloor(requested / step + 1e-8) * step, 8);

      if(lot < minimum || lot > maximum)
         return 0.0;

      if(MathAbs(lot - requested) > 1e-8)
      {
         Print("[HedgeDrift][WARN] Lot rounded down: ",
               DoubleToString(requested, 8), " -> ",
               DoubleToString(lot, 8));
      }

      return lot;
   }

   bool SendLeg(const bool buy, const double lot)
   {
      bool sent;

      if(buy)
         sent = m_trade.Buy(lot, m_symbol, 0.0, 0.0, 0.0,
                            HD_OrderComment());
      else
         sent = m_trade.Sell(lot, m_symbol, 0.0, 0.0, 0.0,
                             HD_OrderComment());

      return CheckResult(sent, buy ? "BUY" : "SELL");
   }

   bool CloseOwnedPositions()
   {
      bool successful = true;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;

         if(PositionGetString(POSITION_SYMBOL) != m_symbol ||
            (ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;

         bool sent = m_trade.PositionClose(ticket);

         if(!CheckResult(sent, "CLOSE ticket="
                               + IntegerToString((long)ticket)))
            successful = false;
      }

      if(Count() > 0)
         successful = false;

      return successful;
   }

public:
   bool Init(const string symbol, const ulong magic)
   {
      m_symbol = symbol;
      m_magic  = magic;
      m_busy   = false;

      if((ENUM_ACCOUNT_MARGIN_MODE)
         AccountInfoInteger(ACCOUNT_MARGIN_MODE)
         != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      {
         Print("[HedgeDrift][ERROR] Phase 2 requires a hedging account.");
         return false;
      }

      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetAsyncMode(false);
      m_trade.SetDeviationInPoints(20);

      if(!m_trade.SetTypeFillingBySymbol(m_symbol))
      {
         Print("[HedgeDrift][ERROR] Cannot set symbol filling mode.");
         return false;
      }

      return true;
   }

   int Count()
   {
      int count = 0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionGetTicket(i) == 0)
            continue;

         if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
            (ulong)PositionGetInteger(POSITION_MAGIC) == m_magic)
            count++;
      }

      return count;
   }

   bool Open(const ENUM_TRADE_DIRECTION direction,
             const double requested_lot)
   {
      if(m_busy)
         return false;

      if(Count() > 0)
      {
         Print("[HedgeDrift][WARN] Open rejected: basket already active.");
         return false;
      }

      if(direction != DIR_BUY_ONLY &&
         direction != DIR_SELL_ONLY &&
         direction != DIR_HEDGE)
         return false;

      if(!TradingAllowed())
         return false;

      double lot = NormalizeLot(requested_lot);
      if(lot <= 0.0)
         return false;

      m_busy = true;
      bool result = false;

      if(direction == DIR_BUY_ONLY)
         result = SendLeg(true, lot);
      else if(direction == DIR_SELL_ONLY)
         result = SendLeg(false, lot);
      else
      {
         if(SendLeg(true, lot))
         {
            // Do not accept an incomplete first leg as a full hedge.
            if(m_trade.ResultRetcode() == TRADE_RETCODE_DONE_PARTIAL)
            {
               Print("[HedgeDrift][WARN] Partial first hedge leg; closing.");
               CloseOwnedPositions();
            }
            else if(SendLeg(false, lot))
            {
               if(m_trade.ResultRetcode() == TRADE_RETCODE_DONE)
                  result = true;
               else
               {
                  Print("[HedgeDrift][WARN] Partial second hedge leg; closing.");
                  CloseOwnedPositions();
               }
            }
            else
            {
               Print("[HedgeDrift][WARN] Second hedge leg failed; closing first.");
               CloseOwnedPositions();
            }

            if(!result && Count() > 0)
            {
               Print("[HedgeDrift][ERROR] Incomplete hedge remains open. ",
                     "Use CLOSE ALL and inspect the terminal.");
            }
         }
      }

      m_busy = false;
      return result;
   }

   bool CloseAll()
   {
      if(m_busy)
         return false;

      if(Count() == 0)
      {
         Print("[HedgeDrift][INFO] Close All: basket already empty.");
         return true;
      }

      if(!TradingAllowed())
         return false;

      m_busy = true;
      bool result = CloseOwnedPositions();
      m_busy = false;

      return result;
   }
};

#endif