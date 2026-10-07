#ifndef HEDGEDRIFT_RUNTIME_STATE_MQH
#define HEDGEDRIFT_RUNTIME_STATE_MQH

#include "Config.mqh"

enum ENUM_HD_CYCLE_STATE
{
   HD_IDLE = 0,
   HD_WAIT_TRIGGER,
   HD_OPENING,
   HD_ACTIVE,
   HD_CLOSING
};

struct HD_RuntimeState
{
   ENUM_HD_CYCLE_STATE cycle;
   ENUM_STRATEGY_MODE strategy;
   ENUM_TRADE_DIRECTION direction;
   ENUM_BE_TYPE be_type;

   bool auto_lot;
   bool hard_cut_loss;
   bool hedge_trigger_lock;
   bool cut_loss_relock;
   bool auto_new_cycle;
   bool cycle_timeout;
   bool auto_be;
   bool rr_target;
   bool session_filter;
   bool session1;
   bool session2;
   bool session3;

   double lock_price;
   datetime state_since;
};

HD_RuntimeState g_hd;

string HD_CycleName(const ENUM_HD_CYCLE_STATE state)
{
   switch(state)
   {
      case HD_IDLE:         return "IDLE";
      case HD_WAIT_TRIGGER: return "WAIT_TRIGGER";
      case HD_OPENING:      return "OPENING";
      case HD_ACTIVE:       return "ACTIVE";
      case HD_CLOSING:      return "CLOSING";
   }

   return "UNKNOWN";
}

void HD_SetCycle(const ENUM_HD_CYCLE_STATE next_state)
{
   if(g_hd.cycle == next_state)
      return;

   Print("[HedgeDrift][INFO] Cycle ",
         HD_CycleName(g_hd.cycle), " -> ",
         HD_CycleName(next_state));

   g_hd.cycle       = next_state;
   g_hd.state_since = TimeCurrent();
}

void HD_InitRuntime()
{
   g_hd.cycle              = HD_IDLE;
   g_hd.strategy           = InpStrategyMode;
   g_hd.direction          = InpTradeDirection;
   g_hd.be_type            = InpBEType;

   g_hd.auto_lot           = InpEnableAutoLot;
   g_hd.hard_cut_loss      = InpEnableHardCutLoss;
   g_hd.hedge_trigger_lock = InpEnableHedgeTriggerLock;
   g_hd.cut_loss_relock    = InpEnableCutLossReLock;
   g_hd.auto_new_cycle     = InpEnableAutoNewCycle;
   g_hd.cycle_timeout      = InpEnableCycleTimeout;
   g_hd.auto_be            = InpEnableAutoBE;
   g_hd.rr_target          = InpEnableRRTarget;
   g_hd.session_filter     = InpEnableSessionFilter;
   g_hd.session1           = InpEnableSession1;
   g_hd.session2           = InpEnableSession2;
   g_hd.session3           = InpEnableSession3;

   g_hd.lock_price         = 0.0;
   g_hd.state_since        = TimeCurrent();
}

#endif