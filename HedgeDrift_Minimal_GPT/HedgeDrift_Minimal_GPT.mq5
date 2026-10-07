#property strict
#property version   "2.10"
#property description "HedgeDrift Minimal - Phase 1 Foundations"

#include "Include\Config.mqh"
#include "Include\RuntimeState.mqh"
#include "Include\AccountingEngine.mqh"
#include "Include\TradeEngine.mqh"
#include "Include\PanelEngine.mqh"
#include "Include\RiskEngine.mqh"
#include "Include\StrategyEngine.mqh"

CHDAccounting     g_accounting;
CHDTradeEngine    g_trade;
CHDPanel          g_panel;
CHDRiskEngine     g_risk;
CHDStrategyEngine g_strategy;

void HD_UpdateDisplay()
{
   g_accounting.RefreshFloating();
   g_panel.Update(g_accounting);
}

bool HD_OpenBasket(const ENUM_TRADE_DIRECTION direction)
{
   if(g_trade.Count() > 0)
   {
      Print("[HedgeDrift][WARN] Open rejected: basket already active.");
      return false;
   }

   if(!g_strategy.SessionAllowed())
   {
      Print("[HedgeDrift][WARN] Open blocked outside enabled sessions.");
      return false;
   }

   HD_SetCycle(HD_OPENING);

   bool opened = g_trade.Open(direction, InpStartLot);
   int count = g_trade.Count();

   // Even a failed hedge may leave a residual position.
   if(count > 0)
   {
      g_strategy.BasketOpened();

      if(!g_risk.BeginBasket())
      {
         Print("[HedgeDrift][ERROR] Risk snapshot failed; closing basket.");
         HD_SetCycle(HD_CLOSING);
         g_trade.CloseAll();

         if(g_trade.Count() == 0)
            g_strategy.BasketClosed();

         HD_SetCycle(g_trade.Count() > 0 ? HD_ACTIVE : HD_IDLE);
         return false;
      }

      HD_SetCycle(HD_ACTIVE);
   }
   else
   {
      HD_SetCycle(HD_IDLE);
   }

   return opened && count > 0;
}

void HD_RunPhase3()
{
   bool risk_action = g_risk.Tick(g_trade, g_accounting);

   if(g_trade.Count() == 0)
   {
      if(g_hd.cycle == HD_ACTIVE || g_hd.cycle == HD_CLOSING)
         HD_SetCycle(HD_IDLE);
   }

   // Never start a new basket in the same pass as an RR close attempt.
   if(!risk_action)
   {
      ENUM_TRADE_DIRECTION direction = DIR_BOTH;

      if(g_strategy.Signal(g_trade.Count(), direction))
         HD_OpenBasket(direction);
   }
}

void HD_SyncManualCycle()
{
   if(g_trade.Count() > 0)
      HD_SetCycle(HD_ACTIVE);
   else
      HD_SetCycle(HD_IDLE);
}

int OnInit()
{
   if(!HD_ValidateConfig())
      return INIT_PARAMETERS_INCORRECT;

   HD_InitRuntime();
   g_risk.Init();
   g_strategy.Init();

   if(!g_accounting.Init(_Symbol, InpMagicNumber, InpBaseCapital))
      return INIT_FAILED;

   if(g_accounting.PositionCount() > 0)
   {
      Print("[HedgeDrift][ERROR] Phase 3 requires an empty initial basket. ",
            "Close existing EA positions before loading.");
      return INIT_FAILED;
   }

   if(!g_trade.Init(_Symbol, InpMagicNumber))
      return INIT_FAILED;

   if(!g_panel.Create())
   {
      Print("[HedgeDrift][ERROR] Panel creation failed.");
      return INIT_FAILED;
   }

   Comment("");

   if(g_accounting.PositionCount() > 0)
   {
      HD_SetCycle(HD_ACTIVE);

      Print("[HedgeDrift][WARN] Existing positions detected. ",
            "Virtual accounting starts fresh; historical PnL is excluded.");
   }

   if(!EventSetTimer(1))
   {
      Print("[HedgeDrift][ERROR] Timer initialization failed. Error=",
            GetLastError());
      return INIT_FAILED;
   }

   Print("[HedgeDrift][INFO] Initialized ", HD_VERSION,
         " Symbol=", _Symbol,
         " Magic=", InpMagicNumber);

   Print("[HedgeDrift][INFO] Phase 3: Lock/Session strategy and risk enabled. ",
         "Fixed StartLot. No persistence or cycle timeout.");

   HD_UpdateDisplay();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   g_panel.Destroy();
   Comment("");

   Print("[HedgeDrift][INFO] Deinitialized. Reason=", reason);
}

void OnTick()
{
   HD_RunPhase3();
}

void OnTimer()
{
   // Timer refreshes UI; automatic signals run on market ticks only.
   HD_UpdateDisplay();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   if(g_accounting.ProcessDeal(trans.deal))
   {
      double close_price = 0.0;

      if(g_hd.cut_loss_relock &&
         g_risk.HardCutPrice(trans.deal, close_price))
      {
         g_strategy.Relock(close_price);
      }

      if(g_trade.Count() == 0)
         g_strategy.BasketClosed();

      HD_SyncManualCycle();
      HD_UpdateDisplay();
   }
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      HD_UpdateDisplay();
      return;
   }

   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   ENUM_HD_PANEL_ACTION action = g_panel.Click(sparam);

   if(action == HD_ACTION_NONE)
   {
      // Refresh header immediately after minimizing/restoring.
      HD_UpdateDisplay();
      return;
   }

   if(action >= HD_ACTION_MODE)
   {
      bool empty = g_trade.Count() == 0;

      if(action == HD_ACTION_MODE)
      {
         if(empty)
         {
            g_hd.strategy =
               (ENUM_STRATEGY_MODE)(((int)g_hd.strategy + 1) % 3);

            g_strategy.ResetLock();
            HD_SetCycle(HD_IDLE);
         }
         else
            Print("[HedgeDrift][WARN] Change mode only with an empty basket.");
      }
      else if(action == HD_ACTION_DIRECTION)
      {
         if(empty)
            g_hd.direction =
               (ENUM_TRADE_DIRECTION)(((int)g_hd.direction + 1) % 4);
         else
            Print("[HedgeDrift][WARN] Change direction only with an empty basket.");
      }
      else if(action == HD_ACTION_BE_TYPE)
      {
         g_hd.be_type = g_hd.be_type == BE_TYPE_FIXED
            ? BE_TYPE_DYNAMIC : BE_TYPE_FIXED;
      }
      else if(action == HD_ACTION_HARD)
      {
         if(empty && InpCutLossPoints > 0)
            g_hd.hard_cut_loss = !g_hd.hard_cut_loss;
         else
            Print("[HedgeDrift][WARN] Change Hard SL only with an empty basket.");
      }
      else if(action == HD_ACTION_BE)
      {
         if(InpBETriggerPoints > 0 &&
            InpBELockPercent > 0.0 && InpBELockPercent < 100.0)
            g_hd.auto_be = !g_hd.auto_be;
         else
            Print("[HedgeDrift][ERROR] Invalid BE parameters.");
      }
      else if(action == HD_ACTION_RR)
      {
         // Initial risk must be captured consistently at basket opening.
         if(empty && InpRRTargetPercent > 0.0 && InpCutLossPoints > 0)
            g_hd.rr_target = !g_hd.rr_target;
         else
            Print("[HedgeDrift][WARN] Change RR only with an empty basket.");
      }
      else if(action == HD_ACTION_SESSION)
      {
         if(!g_hd.session_filter)
         {
            bool valid =
               (!g_hd.session1 || HD_ValidSession(InpSession1Time)) &&
               (!g_hd.session2 || HD_ValidSession(InpSession2Time)) &&
               (!g_hd.session3 || HD_ValidSession(InpSession3Time));

            if(valid)
               g_hd.session_filter = true;
            else
               Print("[HedgeDrift][ERROR] Invalid session settings.");
         }
         else
            g_hd.session_filter = false;
      }
      else if(action == HD_ACTION_RELOCK)
      {
         g_hd.cut_loss_relock = !g_hd.cut_loss_relock;
      }

      HD_UpdateDisplay();
      return;
   }

   if(action == HD_ACTION_REFILL)
   {
      g_accounting.Refill(InpRefillAmount);
   }
   else if(action == HD_ACTION_LOCK)
   {
      MqlTick tick;

      if(SymbolInfoTick(_Symbol, tick) &&
         tick.bid > 0.0 && tick.ask > 0.0)
      {
         g_hd.lock_price = (tick.bid + tick.ask) / 2.0;
         g_strategy.ResetLock();

         Print("[HedgeDrift][INFO] Manual Lock Price=",
               DoubleToString(g_hd.lock_price, _Digits));
      }
      else
      {
         Print("[HedgeDrift][ERROR] No valid quote for Lock Price.");
      }
   }
   else if(action == HD_ACTION_CLOSE)
   {
      if(g_trade.Count() > 0)
         HD_SetCycle(HD_CLOSING);

      g_trade.CloseAll();
      HD_SyncManualCycle();
   }
   else
   {
      if(g_trade.Count() > 0)
      {
         Print("[HedgeDrift][WARN] Open rejected: basket already active.");
      }
      else
      {
         ENUM_TRADE_DIRECTION direction = DIR_BUY_ONLY;

         if(action == HD_ACTION_SELL)
            direction = DIR_SELL_ONLY;
         else if(action == HD_ACTION_HEDGE)
            direction = DIR_HEDGE;

         HD_OpenBasket(direction);
      }
   }

   HD_UpdateDisplay();
}