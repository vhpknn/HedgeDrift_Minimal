#ifndef HEDGEDRIFT_TRADE_ENGINE_MQH
#define HEDGEDRIFT_TRADE_ENGINE_MQH

#include "RuntimeState.mqh"
#include "Persistence.mqh"

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

      if(!HD_ReadValidTick(m_symbol, tick))
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

      if(position_ticket == 0 && g_hd.hard_cut_loss)
      {
         double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
         double tick_size =
            SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);

         int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);

         double minimum_distance =
            SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;

         if(point <= 0.0 || tick_size <= 0.0 ||
            InpCutLossPoints <= 0)
         {
            Print("[HedgeDrift][ERROR] Invalid Hard SL settings.");
            return false;
         }

         double sl = buy
            ? request.price - InpCutLossPoints * point
            : request.price + InpCutLossPoints * point;

         // Round inward: never enlarge the configured risk distance.
         sl = buy
            ? MathCeil(sl / tick_size - 1e-9) * tick_size
            : MathFloor(sl / tick_size + 1e-9) * tick_size;

         sl = NormalizeDouble(sl, digits);

         double market = buy ? tick.bid : tick.ask;
         double distance = buy ? market - sl : sl - market;

         double tolerance = HD_PriceTolerance(
            market, sl, point
         );

         bool valid =
            sl > 0.0 &&
            distance > 0.0 &&
            distance + tolerance >= minimum_distance;

         if(!valid)
         {
            Print("[HedgeDrift][ERROR] Hard SL distance invalid. ",
                  "Order rejected; SL will not be removed or widened.");

            if(g_audit.Active())
            {
               g_audit.Record("ORDER_REJECT_SL",
                  "{\"sl\":" + g_audit.D(sl) +
                  ",\"bid\":" + g_audit.D(tick.bid) +
                  ",\"ask\":" + g_audit.D(tick.ask) +
                  ",\"minimum_distance\":" +
                  g_audit.D(minimum_distance) + "}",
                  0, 0, 0, "WARN");
            }

            return false;
         }

         request.sl = sl;
      }

      if(g_audit.Active())
      {
         g_audit.Record("ORDER_REQUEST",
            "{\"action\":" + g_audit.Q(action) +
            ",\"type\":" + IntegerToString((int)request.type) +
            ",\"volume\":" + g_audit.D(request.volume) +
            ",\"price\":" + g_audit.D(request.price) +
            ",\"bid\":" + g_audit.D(tick.bid) +
            ",\"ask\":" + g_audit.D(tick.ask) +
            ",\"sl\":" + g_audit.D(request.sl) +
            ",\"tp\":" + g_audit.D(request.tp) +
            ",\"filling\":" + IntegerToString((int)request.type_filling) + "}",
            position_ticket);
      }

      ResetLastError();
      bool sent = OrderSend(request, m_result);
      int error = GetLastError();

      if(g_audit.Active())
      {
         g_audit.Record("ORDER_RESULT",
            "{\"sent\":" + g_audit.Bool(sent) +
            ",\"retcode\":" + IntegerToString((int)m_result.retcode) +
            ",\"error\":" + IntegerToString(error) +
            ",\"volume\":" + g_audit.D(m_result.volume) +
            ",\"price\":" + g_audit.D(m_result.price) +
            ",\"comment\":" + g_audit.Q(m_result.comment) + "}",
            position_ticket, m_result.order, m_result.deal,
            sent ? "INFO" : "ERROR");
      }

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

   int CountSide(const ENUM_POSITION_TYPE side)
   {
      int count = 0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionGetTicket(i) == 0)
            continue;

         if(PositionGetString(POSITION_SYMBOL) != m_symbol ||
            (ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;

         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == side)
            count++;
      }

      return count;
   }

   ulong TicketForSide(const ENUM_POSITION_TYPE side)
   {
      ulong found = 0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;

         if(PositionGetString(POSITION_SYMBOL) != m_symbol ||
            (ulong)PositionGetInteger(POSITION_MAGIC) != m_magic ||
            (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != side)
            continue;

         if(found != 0)
            return 0;

         found = ticket;
      }

      return found;
   }

   bool CloseTrailingPosition(const ulong ticket)
   {
      if(m_busy || !TradingAllowed() || PendingCount() > 0)
         return false;

      if(!PositionSelectByTicket(ticket))
         return false;

      if(PositionGetString(POSITION_SYMBOL) != m_symbol ||
         (ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
         return false;

      // Recheck immediately before requesting the close.
      if(PositionGetDouble(POSITION_PROFIT) <= 0.0)
         return false;

      m_busy = true;
      bool result = CloseTicket(ticket);
      m_busy = false;

      return result;
   }

   bool OpenMissingSide(const ENUM_POSITION_TYPE side,
                        const double requested_lot)
   {
      if(m_busy || !TradingAllowed() || PendingCount() > 0)
         return false;

      if(side != POSITION_TYPE_BUY && side != POSITION_TYPE_SELL)
         return false;

      if(CountSide(POSITION_TYPE_BUY) > 1 ||
         CountSide(POSITION_TYPE_SELL) > 1)
      {
         Print("[HedgeDrift][ERROR] Re-Hedge blocked: duplicate side.");
         return false;
      }

      if(CountSide(side) != 0)
         return false;

      double lot = NormalizeLot(requested_lot);
      if(lot <= 0.0)
         return false;

      m_busy = true;
      bool result = SendLeg(side == POSITION_TYPE_BUY, lot);
      m_busy = false;

      return result;
   }

   int PendingCount()
   {
      int count = 0;

      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(OrderGetTicket(i) == 0)
            continue;

         if(OrderGetString(ORDER_SYMBOL) == m_symbol &&
            (ulong)OrderGetInteger(ORDER_MAGIC) == m_magic)
            count++;
      }

      return count;
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

      if(Count() > 0 || PendingCount() > 0)
      {
         Print("[HedgeDrift][WARN] Open rejected: basket/order already active.");
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

   bool ModifyStop(const ulong ticket, const double new_sl)
   {
      if(m_busy || !TradingAllowed())
         return false;

      if(!PositionSelectByTicket(ticket))
         return false;

      if(PositionGetString(POSITION_SYMBOL) != m_symbol ||
         (ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
         return false;

      ENUM_POSITION_TYPE type =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      bool buy = type == POSITION_TYPE_BUY;
      double old_sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);

      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double tick_size =
         SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);

      if(point <= 0.0 || tick_size <= 0.0 || new_sl <= 0.0)
         return false;

      if(old_sl > 0.0)
      {
         if(buy && new_sl <= old_sl + tick_size * 0.5)
            return false;

         if(!buy && new_sl >= old_sl - tick_size * 0.5)
            return false;
      }

      MqlTick tick;
      if(!HD_ReadValidTick(m_symbol, tick))
         return false;

      long stops =
         SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);

      long freeze =
         SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL);

      double stops_distance = (double)stops * point;
      double freeze_distance = (double)freeze * point;

      // Retained for the existing Audit diagnostic field.
      double required = MathMax(stops_distance, freeze_distance);

      double market = buy ? tick.bid : tick.ask;
      double distance = buy ? market - new_sl : new_sl - market;

      double tolerance = HD_PriceTolerance(
         market, new_sl, point
      );

      bool stops_blocked =
         distance + tolerance < stops_distance;

      // Keep a conservative no-touch boundary for Freeze Level.
      bool freeze_blocked =
         freeze > 0 &&
         distance <= freeze_distance + tolerance;

      if(distance <= 0.0 || stops_blocked || freeze_blocked)
      {
         if(g_audit.Active() && g_audit.Gate("SL_DISTANCE_BLOCK", ticket))
         {
            g_audit.Record("SL_DISTANCE_BLOCK",
               "{\"old_sl\":" + g_audit.D(old_sl) +
               ",\"requested_sl\":" + g_audit.D(new_sl) +
               ",\"distance\":" + g_audit.D(distance) +
               ",\"required\":" + g_audit.D(required) + "}",
               ticket, 0, 0, "INFO");
         }

         return false;
      }

      if(g_audit.Active())
         g_audit.ClearGate("SL_DISTANCE_BLOCK", ticket);

      if(old_sl > 0.0 && freeze > 0)
      {
         double old_distance =
            buy ? market - old_sl : old_sl - market;

         double old_tolerance = HD_PriceTolerance(
            market, old_sl, point
         );

         if(old_distance <= freeze_distance + old_tolerance)
         {
            if(g_audit.Active() && g_audit.Gate("SL_FREEZE_BLOCK", ticket))
            {
               g_audit.Record("SL_FREEZE_BLOCK",
                  "{\"old_sl\":" + g_audit.D(old_sl) +
                  ",\"requested_sl\":" + g_audit.D(new_sl) +
                  ",\"old_distance\":" + g_audit.D(old_distance) +
                  ",\"freeze_distance\":" + g_audit.D(freeze * point) + "}",
                  ticket);
            }

            return false;
         }
      }

      if(g_audit.Active())
         g_audit.ClearGate("SL_FREEZE_BLOCK", ticket);

      MqlTradeRequest request;
      MqlTradeResult result;
      ZeroMemory(request);
      ZeroMemory(result);

      request.action   = TRADE_ACTION_SLTP;
      request.symbol   = m_symbol;
      request.position = ticket;
      request.magic    = m_magic;
      request.sl       = new_sl;
      request.tp       = tp;

      m_busy = true;
      bool sent = OrderSend(request, result);
      m_busy = false;

      bool success =
         sent &&
         (result.retcode == TRADE_RETCODE_DONE ||
          result.retcode == TRADE_RETCODE_NO_CHANGES);

      if(g_audit.Active())
      {
         g_audit.Record("SL_MODIFY",
            "{\"old_sl\":" + g_audit.D(old_sl) +
            ",\"requested_sl\":" + g_audit.D(new_sl) +
            ",\"tp_retained\":" + g_audit.D(tp) +
            ",\"bid\":" + g_audit.D(tick.bid) +
            ",\"ask\":" + g_audit.D(tick.ask) +
            ",\"be_type\":" + IntegerToString((int)g_hd.be_type) +
            ",\"success\":" + g_audit.Bool(success) +
            ",\"retcode\":" + IntegerToString((int)result.retcode) + "}",
            ticket, 0, 0, success ? "INFO" : "ERROR");
      }

      Print("[HedgeDrift][", success ? "INFO" : "ERROR", "] ",
            "Modify SL ticket=", ticket,
            " SL=", DoubleToString(new_sl, _Digits),
            " Retcode=", result.retcode,
            " Comment=", result.comment);

      return success;
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