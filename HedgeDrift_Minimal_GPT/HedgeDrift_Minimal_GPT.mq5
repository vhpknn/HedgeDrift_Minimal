#property strict
#property version   "2.10"
#property description "HedgeDrift Minimal - Phase 1 Foundations"

#include "Include\Config.mqh"
#include "Include\RuntimeState.mqh"
#include "Include\AccountingEngine.mqh"
#include "Include\TradeEngine.mqh"
#include "Include\PanelEngine.mqh"

CHDAccounting  g_accounting;
CHDTradeEngine g_trade;
CHDPanel       g_panel;

void HD_UpdateDisplay()
{
   g_accounting.RefreshFloating();
   g_panel.Update(g_accounting);
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

   if(!g_accounting.Init(_Symbol, InpMagicNumber, InpBaseCapital))
      return INIT_FAILED;

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

   Print("[HedgeDrift][WARN] Phase 2: manual trading enabled. ",
         "Fixed StartLot only. No SL/BE/RR and no persistence.");

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
   g_accounting.RefreshFloating();
}

void OnTimer()
{
   if(g_accounting.PositionCount() == 0 &&
      g_hd.cycle == HD_ACTIVE)
      HD_SetCycle(HD_IDLE);

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
      HD_SyncManualCycle();
      HD_UpdateDisplay();
   }
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   ENUM_HD_PANEL_ACTION action = g_panel.Click(sparam);

   if(action == HD_ACTION_NONE)
      return;

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

         HD_SetCycle(HD_OPENING);
         g_trade.Open(direction, InpStartLot);
         HD_SyncManualCycle();
      }
   }

   HD_UpdateDisplay();
}