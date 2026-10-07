#ifndef HEDGEDRIFT_TRADE_ENGINE_MQH
#define HEDGEDRIFT_TRADE_ENGINE_MQH

#include "Config.mqh"

class CHDTradeEngine
{
private:
   MqlTradeResult m_result;
   string m_symbol;
   ulong  m_magic;
   bool   m_busy;

   bool CheckResult(const bool sent, const string action)
   {
      uint code = m_result.retcode;

      bool executed =
         sent &&
         (code == TRADE_RETCODE_DONE ||
          code == TRADE_RETCODE_DONE_PARTIAL);

      Print("[HedgeDrift][", executed ? "INFO" : "ERROR", "] ",
            action,
            " Retcode=", code,
            " Deal=", m_result.deal,
            " Order=", m_result.order,
            " Volume=", DoubleToString(m_result.volume, 8),
            " Comment=", m_result.comment);

      if(sent && code == TRADE_RETCODE_PLACED)
      {
         Print("[HedgeDrift][WARN] Request accepted but execution ",
               "is not confirmed. Inspect terminal orders/positions; ",
               "do not immediately repeat the request.");
      }

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

   bool SelectFilling(ENUM_ORDER_TYPE_FILLING &filling)
   {
      long execution = 0;
      long flags     = 0;

      if(!SymbolInfoInteger(m_symbol, SYMBOL_TRADE_EXEMODE, execution) ||
         !SymbolInfoInteger(m_symbol, SYMBOL_FILLING_MODE, flags))
      {
         Print("[HedgeDrift][ERROR] Cannot read symbol execution settings.");
         return false;
      }

      if(execution == SYMBOL_TRADE_EXECUTION_REQUEST ||
         execution == SYMBOL_TRADE_EXECUTION_INSTANT)
      {
         filling = ORDER_FILLING_FOK;
         return true;
      }

      if((flags & SYMBOL_FILLING_FOK) != 0)
      {
         filling = ORDER_FILLING_FOK;
         return true;
      }

      if((flags & SYMBOL_FILLING_IOC) != 0)
      {
         filling = ORDER_FILLING_IOC;
         return true;
      }

      Print("[HedgeDrift][ERROR] No FOK/IOC filling supported. ",
            "RETURN-only execution is not supported in this phase.");
      return false;
   }

   bool SendMarket(const bool buy,
                   const double volume,
                   const ulong position_ticket,
                   const string action)
   {
      ZeroMemory(m_result);

      ENUM_ORDER_TYPE_FILLING filling = ORDER_FILLING_FOK;
      if(!SelectFilling(filling))
         return false;

      MqlTick tick;
      ZeroMemory(tick);

      if(!SymbolInfoTick(m_symbol, tick) ||
         tick.bid <= 0.0 || tick.ask <= 0.0)
      {
         Print("[HedgeDrift][ERROR] No valid quote for ", action);
         return false;
      }

      MqlTradeRequest request;
      ZeroMemory(request);

      request.action       = TRADE_ACTION_DEAL;
      request.symbol       = m_symbol;
      request.magic        = m_magic;
      request.position     = position_ticket;
      request.volume       = volume;
      request.type         = buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      request.price        = buy ? tick.ask : tick.bid;
      request.deviation    = 20;
      request.type_filling = filling;
      request.comment      = HD_OrderComment();

      ResetLastError();
      bool sent = OrderSend(request, m_result);
      int error = GetLastError();

      if(!sent)
      {
         Print("[HedgeDrift][ERROR] OrderSend failed. Action=",
               action, " Error=", error);
      }

      return CheckResult(sent, action);
   }

   bool SendLeg(const bool buy, const double lot)
   {
      return SendMarket(buy, lot, 0, buy ? "BUY" : "SELL");
   }

   bool CloseTicket(const ulong ticket)
   {
      if(!PositionSelectByTicket(ticket))
      {
         Print("[HedgeDrift][WARN] Position unavailable: ", ticket);
         return false;
      }

      if(PositionGetString(POSITION_SYMBOL) != m_symbol ||
         (ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
      {
         Print("[HedgeDrift][ERROR] Refusing to close foreign position: ",
               ticket);
         return false;
      }

      ENUM_POSITION_TYPE type =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double volume = PositionGetDouble(POSITION_VOLUME);

      if(volume <= 0.0)
         return false;

      // Close SELL with BUY; close BUY with SELL.
      bool buy = (type == POSITION_TYPE_SELL);

      return SendMarket(
         buy,
         volume,
         ticket,
         "CLOSE ticket=" + IntegerToString((long)ticket)
      );
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

         if(!CloseTicket(ticket))
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

      ZeroMemory(m_result);

      ENUM_ORDER_TYPE_FILLING filling = ORDER_FILLING_FOK;
      if(!SelectFilling(filling))
         return false;

      Print("[HedgeDrift][INFO] Native OrderSend engine ready. Filling=",
            EnumToString(filling));

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
            if(m_result.retcode == TRADE_RETCODE_DONE_PARTIAL)
            {
               Print("[HedgeDrift][WARN] Partial first hedge leg; closing.");
               CloseOwnedPositions();
            }
            else if(SendLeg(false, lot))
            {
               if(m_result.retcode == TRADE_RETCODE_DONE)
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