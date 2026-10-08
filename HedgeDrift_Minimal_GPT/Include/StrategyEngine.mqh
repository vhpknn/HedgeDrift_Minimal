#ifndef HEDGEDRIFT_STRATEGY_ENGINE_MQH
#define HEDGEDRIFT_STRATEGY_ENGINE_MQH

#include "RuntimeState.mqh"
#include "TradeEngine.mqh"
#include "Persistence.mqh"

class CHDStrategyEngine
{
private:
   double m_previous;
   bool m_previous_valid;
   bool m_spent;
   bool m_seen_basket;
   bool m_relock_pending;
   datetime m_wait_since;

   bool m_rh_armed;
   bool m_buy_wait;
   bool m_sell_wait;
   datetime m_buy_since;
   datetime m_sell_since;

   bool m_rh_intent;
   ENUM_POSITION_TYPE m_rh_side;
   datetime m_rh_intent_since;

   bool InSession(const string range, const int now_minutes)
   {
      int start_minutes = 0;
      int end_minutes = 0;

      if(!HD_ParseClock(StringSubstr(range, 0, 5),
                        false, start_minutes) ||
         !HD_ParseClock(StringSubstr(range, 6, 5),
                        true, end_minutes))
         return false;

      if(start_minutes < end_minutes)
         return now_minutes >= start_minutes &&
                now_minutes < end_minutes;

      return now_minutes >= start_minutes ||
             now_minutes < end_minutes;
   }

public:
   void Init()
   {
      m_previous = 0.0;
      m_previous_valid = false;
      m_spent = false;
      m_seen_basket = false;
      m_relock_pending = false;
      m_wait_since = TimeCurrent();

      m_rh_armed = false;
      m_buy_wait = false;
      m_sell_wait = false;
      m_buy_since = 0;
      m_sell_since = 0;
      m_rh_intent = false;
      m_rh_side = POSITION_TYPE_BUY;
      m_rh_intent_since = 0;
   }

   void SaveState(CHDPersistence &state)
   {
      state.PutU("strategy_spent", (ulong)m_spent);
      state.PutU("strategy_seen", (ulong)m_seen_basket);
      state.PutU("strategy_relock", (ulong)m_relock_pending);
      state.PutU("strategy_wait", (ulong)m_wait_since);

      state.PutU("rh_version", 1);
      state.PutU("rh_armed", (ulong)m_rh_armed);
      state.PutU("rh_buy_wait", (ulong)m_buy_wait);
      state.PutU("rh_sell_wait", (ulong)m_sell_wait);
      state.PutU("rh_buy_since", (ulong)m_buy_since);
      state.PutU("rh_sell_since", (ulong)m_sell_since);
      state.PutU("rh_intent", (ulong)m_rh_intent);
      state.PutU("rh_side", (ulong)m_rh_side);
      state.PutU("rh_intent_since", (ulong)m_rh_intent_since);
   }

   bool LoadState(CHDPersistence &state)
   {
      m_spent = state.B("strategy_spent");
      m_seen_basket = state.B("strategy_seen");
      m_relock_pending = state.B("strategy_relock");
      m_wait_since = (datetime)state.U("strategy_wait");

      m_rh_armed = false;
      m_buy_wait = false;
      m_sell_wait = false;
      m_buy_since = 0;
      m_sell_since = 0;
      m_rh_intent = false;
      m_rh_side = POSITION_TYPE_BUY;
      m_rh_intent_since = 0;

      bool extended = state.Has("rh_version");

      if(state.Has("feature_version") && !extended)
         return false;

      if(extended)
      {
         if(state.I("rh_version") != 1)
            return false;

         m_rh_armed = state.B("rh_armed");
         m_buy_wait = state.B("rh_buy_wait");
         m_sell_wait = state.B("rh_sell_wait");
         m_buy_since = (datetime)state.U("rh_buy_since");
         m_sell_since = (datetime)state.U("rh_sell_since");
         m_rh_intent = state.B("rh_intent");

         int side = state.I("rh_side");
         if(side > 1)
            return false;

         m_rh_side = (ENUM_POSITION_TYPE)side;
         m_rh_intent_since = (datetime)state.U("rh_intent_since");

         if((m_buy_wait && m_buy_since <= 0) ||
            (m_sell_wait && m_sell_since <= 0) ||
            (m_rh_intent && m_rh_intent_since <= 0))
            return false;
      }

      // Do not replay a crossing from the EA downtime.
      m_previous = 0.0;
      m_previous_valid = false;

      return state.Good() && m_wait_since >= 0;
   }

   void OpenFailed()
   {
      m_spent = false;
      m_previous_valid = false;
      m_wait_since = TimeCurrent();
   }

   bool ReHedgeActive()
   {
      return InpEnableAutoReHedge && m_rh_armed;
   }

   void ArmReHedge()
   {
      if(!InpEnableAutoReHedge)
         return;

      m_rh_armed = true;
      m_buy_wait = false;
      m_sell_wait = false;
      m_buy_since = 0;
      m_sell_since = 0;
      m_rh_intent = false;
      m_rh_intent_since = 0;

      m_seen_basket = true;
      m_spent = true;

      Print("[HedgeDrift][INFO] Auto Re-Hedge armed for this hedge round.");
   }

   void StopReHedge()
   {
      m_rh_armed = false;
      m_buy_wait = false;
      m_sell_wait = false;
      m_rh_intent = false;
      m_rh_intent_since = 0;
   }

   void ObserveHedgeClose(const ulong deal, CHDTradeEngine &trade)
   {
      if(!ReHedgeActive() || !HistoryDealSelect(deal))
         return;

      ENUM_DEAL_ENTRY entry =
         (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);

      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
         return;

      ENUM_DEAL_TYPE type =
         (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal, DEAL_TYPE);

      if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL)
         return;

      ENUM_POSITION_TYPE missing =
         type == DEAL_TYPE_SELL ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;

      if(trade.CountSide(missing) > 0)
         return;

      datetime closed =
         (datetime)HistoryDealGetInteger(deal, DEAL_TIME);

      if(closed <= 0)
         return;

      if(missing == POSITION_TYPE_BUY)
      {
         m_buy_wait = true;
         m_buy_since = closed;
      }
      else
      {
         m_sell_wait = true;
         m_sell_since = closed;
      }

      Print("[HedgeDrift][INFO] Missing-side timer: ",
            missing == POSITION_TYPE_BUY ? "BUY" : "SELL",
            " Since=", TimeToString(closed, TIME_DATE | TIME_SECONDS));
   }

   bool ReHedgeSignal(CHDTradeEngine &trade,
                      ENUM_POSITION_TYPE &side)
   {
      if(!ReHedgeActive() || m_rh_intent ||
         trade.PendingCount() > 0)
         return false;

      int buys = trade.CountSide(POSITION_TYPE_BUY);
      int sells = trade.CountSide(POSITION_TYPE_SELL);

      if(buys > 1 || sells > 1)
         return false;

      if(buys > 0)
         m_buy_wait = false;

      if(sells > 0)
         m_sell_wait = false;

      datetime now = TimeCurrent();

      if(buys == 0 && m_buy_wait &&
         now - m_buy_since >= InpTimeoutSeconds)
      {
         side = POSITION_TYPE_BUY;
         return true;
      }

      if(sells == 0 && m_sell_wait &&
         now - m_sell_since >= InpTimeoutSeconds)
      {
         side = POSITION_TYPE_SELL;
         return true;
      }

      return false;
   }

   void BeginReHedgeIntent(const ENUM_POSITION_TYPE side)
   {
      m_rh_intent = true;
      m_rh_side = side;
      m_rh_intent_since = TimeCurrent();
   }

   bool HasReHedgeIntent()
   {
      return m_rh_intent;
   }

   ENUM_POSITION_TYPE ReHedgeIntentSide()
   {
      return m_rh_side;
   }

   datetime ReHedgeIntentTime()
   {
      return m_rh_intent_since;
   }

   void FinishReHedgeIntent(const bool filled)
   {
      if(filled)
      {
         if(m_rh_side == POSITION_TYPE_BUY)
            m_buy_wait = false;
         else
            m_sell_wait = false;
      }
      else
      {
         if(m_rh_side == POSITION_TYPE_BUY)
         {
            // Preserve a later close observed during history replay.
            if(!m_buy_wait || m_buy_since <= m_rh_intent_since)
               m_buy_since = TimeCurrent();

            m_buy_wait = true;
         }
         else
         {
            if(!m_sell_wait || m_sell_since <= m_rh_intent_since)
               m_sell_since = TimeCurrent();

            m_sell_wait = true;
         }
      }

      m_rh_intent = false;
      m_rh_intent_since = 0;
   }

   bool SessionAllowed()
   {
      if(g_hd.strategy != MODE_LOCK_PRICE || !g_hd.session_filter)
         return true;

      MqlDateTime server;
      if(!TimeToStruct(TimeCurrent(), server))
         return false;

      int minutes = server.hour * 60 + server.min;

      if(g_hd.session1 && InSession(InpSession1Time, minutes))
         return true;

      if(g_hd.session2 && InSession(InpSession2Time, minutes))
         return true;

      if(g_hd.session3 && InSession(InpSession3Time, minutes))
         return true;

      return false;
   }

   void ResetLock()
   {
      m_previous_valid = false;
      m_spent = false;
      m_wait_since = TimeCurrent();
   }

   void Relock(const double price)
   {
      if(price <= 0.0)
         return;

      g_hd.lock_price = price;
      m_previous_valid = false;
      m_relock_pending = true;

      if(!m_seen_basket)
      {
         m_spent = false;
         m_wait_since = TimeCurrent();
      }

      Print("[HedgeDrift][INFO] HardCut Re-Lock=",
            DoubleToString(price, _Digits));
   }

   void BasketOpened()
   {
      m_seen_basket = true;
      m_spent = true;
      m_relock_pending = false;
   }

   void BasketClosed()
   {
      if(!m_seen_basket)
         return;

      m_seen_basket = false;
      m_spent = !(g_hd.auto_new_cycle || m_relock_pending);
      m_relock_pending = false;

      // Require a fresh crossing; Timeout starts from basket closure.
      m_previous_valid = false;
      m_wait_since = TimeCurrent();
   }

   bool Signal(const int positions, ENUM_TRADE_DIRECTION &direction)
   {
      MqlTick tick;
      if(!SymbolInfoTick(_Symbol, tick) ||
         tick.bid <= 0.0 || tick.ask <= 0.0)
         return false;

      double price = (tick.bid + tick.ask) / 2.0;

      if(g_hd.lock_price <= 0.0)
      {
         g_hd.lock_price = price;
         m_previous = price;
         m_previous_valid = true;

         Print("[HedgeDrift][INFO] Initial Lock Price=",
               DoubleToString(price, _Digits));
         return false;
      }

      if(positions > 0)
      {
         m_previous = price;
         m_previous_valid = true;
         return false;
      }

      if(g_hd.strategy == MODE_TIMEOUT_HEDGE)
      {
         m_previous = price;
         m_previous_valid = true;

         if(!g_hd.cycle_timeout || m_spent)
            return false;

         HD_SetCycle(HD_WAIT_TRIGGER);

         if(m_wait_since <= 0)
         {
            m_wait_since = TimeCurrent();
            return false;
         }

         if(TimeCurrent() - m_wait_since < InpTimeoutSeconds)
            return false;

         direction = DIR_HEDGE;
         m_spent = true;

         Print("[HedgeDrift][INFO] Empty-basket timeout reached. ",
               "Opening Hedge.");

         return true;
      }

      if(g_hd.strategy == MODE_MANUAL_FREE ||
         !g_hd.hedge_trigger_lock || m_spent)
      {
         m_previous = price;
         m_previous_valid = true;
         return false;
      }

      HD_SetCycle(HD_WAIT_TRIGGER);

      if(!m_previous_valid)
      {
         m_previous = price;
         m_previous_valid = true;
         return false;
      }

      double distance =
         InpLockDistancePoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT);

      double lower = g_hd.lock_price - distance;
      double upper = g_hd.lock_price + distance;

      bool cross_buy = m_previous > lower && price <= lower;
      bool cross_sell = m_previous < upper && price >= upper;

      // Update outside sessions too: do not replay an old crossing.
      m_previous = price;

      if(!SessionAllowed())
         return false;

      bool allowed_buy =
         g_hd.direction == DIR_BUY_ONLY ||
         g_hd.direction == DIR_BOTH ||
         g_hd.direction == DIR_HEDGE;

      bool allowed_sell =
         g_hd.direction == DIR_SELL_ONLY ||
         g_hd.direction == DIR_BOTH ||
         g_hd.direction == DIR_HEDGE;

      if(cross_buy && allowed_buy)
      {
         direction = g_hd.direction == DIR_HEDGE
            ? DIR_HEDGE : DIR_BUY_ONLY;
      }
      else if(cross_sell && allowed_sell)
      {
         direction = g_hd.direction == DIR_HEDGE
            ? DIR_HEDGE : DIR_SELL_ONLY;
      }
      else
      {
         return false;
      }

      // One request per crossing; failed orders are not spam-retried.
      m_spent = true;
      return true;
   }
};

#endif