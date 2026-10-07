#ifndef HEDGEDRIFT_STRATEGY_ENGINE_MQH
#define HEDGEDRIFT_STRATEGY_ENGINE_MQH

#include "RuntimeState.mqh"

class CHDStrategyEngine
{
private:
   double m_previous;
   bool m_previous_valid;
   bool m_spent;
   bool m_seen_basket;
   bool m_relock_pending;

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
   }

   bool SessionAllowed()
   {
      if(g_hd.strategy != MODE_TIME_SESSION || !g_hd.session_filter)
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
   }

   void Relock(const double price)
   {
      if(price <= 0.0)
         return;

      g_hd.lock_price = price;
      m_previous_valid = false;
      m_relock_pending = true;

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

      // Require a fresh crossing after basket closure.
      m_previous_valid = false;
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