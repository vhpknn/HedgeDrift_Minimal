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
#include "Include\Persistence.mqh"

CHDAccounting     g_accounting;
CHDTradeEngine    g_trade;
CHDPanel          g_panel;
CHDRiskEngine     g_risk;
CHDStrategyEngine g_strategy;
CHDPersistence   g_state;

bool g_initialized = false;
bool g_recovery_ok = false;
bool g_storage_ok = true;
datetime g_last_replay = 0;

void HD_UpdateDisplay()
{
   g_accounting.RefreshFloating();
   g_panel.Update(g_accounting);
}

void HD_AuditRuntime(const string event = "RUNTIME_STATE",
                     const bool force = false)
{
   if(!g_audit.Active())
      return;

   static string previous_key = "";

   int buys = g_trade.CountSide(POSITION_TYPE_BUY);
   int sells = g_trade.CountSide(POSITION_TYPE_SELL);
   int pending = g_trade.PendingCount();

   string flags =
      IntegerToString((int)g_hd.auto_lot) + "," +
      IntegerToString((int)g_hd.hard_cut_loss) + "," +
      IntegerToString((int)g_hd.hedge_trigger_lock) + "," +
      IntegerToString((int)g_hd.cut_loss_relock) + "," +
      IntegerToString((int)g_hd.auto_new_cycle) + "," +
      IntegerToString((int)g_hd.cycle_timeout) + "," +
      IntegerToString((int)g_hd.auto_be) + "," +
      IntegerToString((int)g_hd.rr_target) + "," +
      IntegerToString((int)g_hd.session_filter) + "," +
      IntegerToString((int)g_hd.session1) + "," +
      IntegerToString((int)g_hd.session2) + "," +
      IntegerToString((int)g_hd.session3);

   string key =
      IntegerToString((int)g_hd.cycle) + "|" +
      IntegerToString((int)g_hd.strategy) + "|" +
      IntegerToString((int)g_hd.direction) + "|" +
      IntegerToString((int)g_hd.be_type) + "|" +
      flags + "|" +
      IntegerToString(buys) + "|" +
      IntegerToString(sells) + "|" +
      IntegerToString(pending) + "|" +
      IntegerToString((int)g_recovery_ok) + "|" +
      IntegerToString((int)g_storage_ok) + "|" +
      DoubleToString(g_hd.lock_price, _Digits);

   if(!force && key == previous_key)
      return;

   previous_key = key;

   g_audit.Record(event,
      "{\"direction\":" + IntegerToString((int)g_hd.direction) +
      ",\"be_type\":" + IntegerToString((int)g_hd.be_type) +
      ",\"runtime_flags\":" + g_audit.Q(flags) +
      ",\"buy_count\":" + IntegerToString(buys) +
      ",\"sell_count\":" + IntegerToString(sells) +
      ",\"pending_count\":" + IntegerToString(pending) +
      ",\"lock\":" + g_audit.D(g_hd.lock_price) +
      ",\"eq\":" + g_audit.D(g_accounting.Balance()) +
      ",\"or\":" + g_audit.D(g_accounting.Floating()) +
      ",\"tt\":" + g_audit.D(g_accounting.Equity()) +
      ",\"initial_risk\":" + g_audit.D(g_risk.InitialRisk()) +
      ",\"target\":" + g_audit.D(g_risk.TargetMoney()) +
      ",\"rehedge_active\":" + g_audit.Bool(g_strategy.ReHedgeActive()) +
      ",\"recovery_ok\":" + g_audit.Bool(g_recovery_ok) +
      ",\"storage_ok\":" + g_audit.Bool(g_storage_ok) + "}");
}

bool HD_SaveState()
{
   if(!g_initialized || !g_recovery_ok)
      return false;

   if(!g_state.Enabled())
   {
      g_storage_ok = true;
      return true;
   }

   g_state.Begin();
   HD_SaveRuntime(g_state);
   g_accounting.SaveState(g_state);
   g_risk.SaveState(g_state);
   g_strategy.SaveState(g_state);

   bool success = g_state.Commit();

   if(!success && g_storage_ok)
   {
      if(g_audit.Active())
         g_audit.Record("STATE_SAVE_FAILED", "{}",
                        0, 0, 0, "ERROR");

      Print("[HedgeDrift][ERROR] State save failed. ",
            "New entries blocked; existing risk management remains active.");
   }

   if(success && !g_storage_ok)
   {
      Print("[HedgeDrift][INFO] State storage recovered.");

      if(g_audit.Active())
         g_audit.Record("STATE_STORAGE_RECOVERED");
   }

   g_storage_ok = success;

   if(success)
      g_risk.MarkSaved();

   return success;
}

bool HD_ReconcileDeals(const bool force)
{
   if(!force && g_last_replay == TimeCurrent())
      return g_accounting.Healthy();

   if(g_risk.Closing())
      g_strategy.StopReHedge();

   ulong tickets[];

   if(!g_accounting.ReplayTickets(tickets))
   {
      g_recovery_ok = false;
      Print("[HedgeDrift][ERROR] History reconciliation failed.");
      return false;
   }

   for(int i = 0; i < ArraySize(tickets); i++)
   {
      if(!g_accounting.ProcessDeal(tickets[i]))
      {
         if(!g_accounting.Healthy())
         {
            g_recovery_ok = false;
            return false;
         }

         continue;
      }

      g_strategy.ObserveHedgeClose(tickets[i], g_trade);

      double close_price = 0.0;

      if(g_hd.strategy == MODE_LOCK_PRICE &&
         g_hd.cut_loss_relock &&
         g_risk.HardCutPrice(tickets[i], close_price))
      {
         g_strategy.Relock(close_price);
      }
   }

   // Finish the basket only after the replay batch is processed.
   if(g_trade.Count() == 0 && g_trade.PendingCount() == 0)
   {
      if(!g_strategy.ReHedgeActive())
         g_strategy.BasketClosed();

      if(g_hd.cycle == HD_ACTIVE ||
         g_hd.cycle == HD_CLOSING ||
         g_hd.cycle == HD_OPENING)
         HD_SetCycle(HD_IDLE);
   }
   else if(g_trade.Count() > 0)
   {
      HD_SetCycle(g_risk.Closing() ? HD_CLOSING : HD_ACTIVE);
   }

   g_accounting.RefreshFloating();
   g_last_replay = TimeCurrent();
   return g_accounting.Healthy();
}

bool HD_OpenBasket(const ENUM_TRADE_DIRECTION direction,
                   const bool manual)
{
   if(!g_recovery_ok || !g_storage_ok ||
      !HD_ReconcileDeals(true))
   {
      Print("[HedgeDrift][ERROR] Open blocked: recovery/storage not ready.");
      return false;
   }

   if(g_trade.Count() > 0 || g_trade.PendingCount() > 0)
   {
      Print("[HedgeDrift][WARN] Open rejected: basket/order already active.");
      return false;
   }

   // Manual bypasses strategy entry filters, not trade/risk safety.
   if(!manual && !g_strategy.SessionAllowed())
   {
      Print("[HedgeDrift][WARN] Automatic entry blocked outside sessions.");
      return false;
   }

   g_strategy.StopReHedge();
   g_risk.Init();
   HD_SetCycle(HD_OPENING);

   // Save intent first; never repeat it blindly after a restart.
   if(!HD_SaveState())
      return false;

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

      if(opened && direction == DIR_HEDGE &&
         g_trade.CountSide(POSITION_TYPE_BUY) == 1 &&
         g_trade.CountSide(POSITION_TYPE_SELL) == 1)
      {
         g_strategy.ArmReHedge();
      }
   }
   else
   {
      HD_SetCycle(HD_IDLE);
   }

   if(count == 0 && g_trade.PendingCount() == 0)
      g_strategy.OpenFailed();

   HD_SaveState();
   return opened && count > 0;
}

struct HD_ReHedgeHistory
{
   ulong identifier;
   double opened_volume;
   double closed_volume;
   double original_sl;
   double volume_tolerance;
   datetime closed_time;
};

bool HD_ReadReHedgeHistory(HD_ReHedgeHistory &evidence)
{
   ZeroMemory(evidence);

   ENUM_POSITION_TYPE side = g_strategy.ReHedgeIntentSide();

   if(side != POSITION_TYPE_BUY && side != POSITION_TYPE_SELL)
      return false;

   double requested = g_strategy.ReHedgeRequestedVolume();
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(!MathIsValidNumber(requested) || requested <= 0.0 ||
      !MathIsValidNumber(step) || step <= 0.0)
      return false;

   ulong order = g_strategy.ReHedgeOrder();
   ulong receipt_deal = g_strategy.ReHedgeDeal();

   ENUM_DEAL_TYPE opening_type =
      side == POSITION_TYPE_BUY ? DEAL_TYPE_BUY : DEAL_TYPE_SELL;

   ENUM_ORDER_TYPE order_type =
      side == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   if(receipt_deal != 0)
   {
      if(!HistoryDealSelect(receipt_deal))
         return false;

      if(HistoryDealGetString(receipt_deal, DEAL_SYMBOL) != _Symbol ||
         (ulong)HistoryDealGetInteger(receipt_deal, DEAL_MAGIC) !=
            InpMagicNumber ||
         (ENUM_DEAL_ENTRY)HistoryDealGetInteger(receipt_deal, DEAL_ENTRY) !=
            DEAL_ENTRY_IN ||
         (ENUM_DEAL_TYPE)HistoryDealGetInteger(receipt_deal, DEAL_TYPE) !=
            opening_type)
         return false;

      ulong deal_order =
         (ulong)HistoryDealGetInteger(receipt_deal, DEAL_ORDER);

      if(deal_order == 0 || (order != 0 && order != deal_order))
         return false;

      order = deal_order;
   }

   if(order == 0 || !HistoryOrderSelect(order))
      return false;

   if(HistoryOrderGetString(order, ORDER_SYMBOL) != _Symbol ||
      (ulong)HistoryOrderGetInteger(order, ORDER_MAGIC) != InpMagicNumber ||
      (ENUM_ORDER_TYPE)HistoryOrderGetInteger(order, ORDER_TYPE) !=
         order_type ||
      (ENUM_ORDER_STATE)HistoryOrderGetInteger(order, ORDER_STATE) !=
         ORDER_STATE_FILLED)
      return false;

   datetime setup =
      (datetime)HistoryOrderGetInteger(order, ORDER_TIME_SETUP);

   if(setup < g_strategy.ReHedgeIntentTime() - 1)
      return false;

   evidence.identifier =
      (ulong)HistoryOrderGetInteger(order, ORDER_POSITION_ID);

   evidence.original_sl = HistoryOrderGetDouble(order, ORDER_SL);

   if(evidence.identifier == 0 ||
      !MathIsValidNumber(evidence.original_sl) ||
      evidence.original_sl < 0.0 ||
      (g_hd.hard_cut_loss && evidence.original_sl <= 0.0))
      return false;

   if(!HistorySelectByPosition(evidence.identifier))
      return false;

   bool receipt_seen = receipt_deal == 0;
   long last_close_msc = 0;
   int total = HistoryDealsTotal();

   for(int i = 0; i < total; i++)
   {
      ulong deal = HistoryDealGetTicket(i);

      if(deal == 0)
         return false;

      ENUM_DEAL_TYPE type =
         (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal, DEAL_TYPE);

      if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL)
         continue;

      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol ||
         (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID) !=
            evidence.identifier)
         return false;

      double volume = HistoryDealGetDouble(deal, DEAL_VOLUME);

      if(!MathIsValidNumber(volume) || volume <= 0.0)
         return false;

      ENUM_DEAL_ENTRY entry =
         (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);

      if(entry == DEAL_ENTRY_IN)
      {
         if(type != opening_type ||
            (ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) !=
               InpMagicNumber ||
            (ulong)HistoryDealGetInteger(deal, DEAL_ORDER) != order)
            return false;

         evidence.opened_volume += volume;

         if(deal == receipt_deal)
            receipt_seen = true;
      }
      else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
      {
         if(type == opening_type)
            return false;

         evidence.closed_volume += volume;

         long closed_msc =
            HistoryDealGetInteger(deal, DEAL_TIME_MSC);

         if(closed_msc > last_close_msc)
            last_close_msc = closed_msc;
      }
      else
         return false;
   }

   if(!receipt_seen ||
      !MathIsValidNumber(evidence.opened_volume) ||
      !MathIsValidNumber(evidence.closed_volume))
      return false;

   evidence.volume_tolerance = MathMax(
      step * 1e-7,
      8.0 * DBL_EPSILON *
         MathMax(requested, evidence.opened_volume)
   );

   if(MathAbs(evidence.opened_volume - requested) >
         evidence.volume_tolerance ||
      evidence.closed_volume >
         evidence.opened_volume + evidence.volume_tolerance)
      return false;

   evidence.closed_time = (datetime)(last_close_msc / 1000);

   return true;
}

bool HD_ResolveReHedgeIntent()
{
   if(!g_strategy.HasReHedgeIntent())
      return true;

   if(g_trade.PendingCount() > 0)
      return true;

   ENUM_POSITION_TYPE side = g_strategy.ReHedgeIntentSide();
   int count = g_trade.CountSide(side);

   if(count > 1)
      return false;

   if(g_strategy.ReHedgeNoExecution())
   {
      if(count != 0)
         return false;

      if(g_audit.Active())
      {
         g_audit.Record("RH_NO_EXECUTION_CONFIRMED",
            "{\"side\":" + IntegerToString((int)side) +
            ",\"intent_since\":" +
            g_audit.U((ulong)g_strategy.ReHedgeIntentTime()) + "}");
      }

      g_strategy.FinishReHedgeIntent(false);
      return true;
   }

   HD_ReHedgeHistory evidence;

   if(!HD_ReadReHedgeHistory(evidence))
   {
      if(g_recovery_ok)
      {
         Print("[HedgeDrift][ERROR] Re-Hedge history evidence incomplete. ",
               "Partial, unknown or conflicting execution remains blocked.");

         if(g_audit.Active())
            g_audit.Record("RH_HISTORY_UNRESOLVED",
               "{\"side\":" + IntegerToString((int)side) + "}",
               0, g_strategy.ReHedgeOrder(),
               g_strategy.ReHedgeDeal(), "ERROR");
      }

      return false;
   }

   double remaining =
      evidence.opened_volume - evidence.closed_volume;

   if(count == 0)
   {
      if(MathAbs(remaining) > evidence.volume_tolerance ||
         evidence.closed_time <= 0)
         return false;

      // Do not replay a historical Re-Lock out of chronological order.
      if(g_hd.strategy == MODE_LOCK_PRICE && g_hd.cut_loss_relock)
      {
         if(g_recovery_ok)
            Print("[HedgeDrift][ERROR] Closed replacement requires ",
                  "chronological HardCut Re-Lock recovery.");

         return false;
      }

      if(!HD_ReconcileDeals(true))
         return false;

      if(!g_strategy.FinishClosedReHedgeIntent(evidence.closed_time))
         return false;

      HD_SetCycle(HD_IDLE);

      if(g_audit.Active())
      {
         g_audit.Record("RH_FILLED_THEN_CLOSED",
            "{\"side\":" + IntegerToString((int)side) +
            ",\"identifier\":" + g_audit.U(evidence.identifier) +
            ",\"closed_time\":" +
            g_audit.U((ulong)evidence.closed_time) +
            ",\"opened_volume\":" + g_audit.D(evidence.opened_volume) +
            ",\"closed_volume\":" + g_audit.D(evidence.closed_volume) + "}");
      }

      return true;
   }

   ulong ticket = g_trade.TicketForSide(side);

   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return false;

   ulong live_identifier =
      (ulong)PositionGetInteger(POSITION_IDENTIFIER);

   ENUM_POSITION_TYPE live_side =
      (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   double live_volume = PositionGetDouble(POSITION_VOLUME);

   if(live_identifier != evidence.identifier ||
      live_side != side ||
      remaining <= evidence.volume_tolerance ||
      !MathIsValidNumber(live_volume) ||
      MathAbs(live_volume - remaining) > evidence.volume_tolerance)
   {
      Print("[HedgeDrift][ERROR] Live replacement does not match ",
            "the saved request and history evidence.");
      return false;
   }

   if(!g_risk.RegisterReplacement(ticket, evidence.original_sl))
      return false;

   g_strategy.FinishReHedgeIntent(true);
   HD_SetCycle(HD_ACTIVE);

   Print("[HedgeDrift][INFO] Re-Hedge filled: ",
         side == POSITION_TYPE_BUY ? "BUY" : "SELL",
         " Ticket=", ticket);

   return true;
}

bool HD_RunTrailingHelper()
{
   g_risk.UpdateTrailingPeaks();

   ulong tickets[];
   bool candidates = g_risk.PrepareTrailing(tickets);

   if(g_risk.PeakDirty() || candidates)
   {
      // Save peak and close intent before sending any trailing close.
      if(!HD_SaveState())
         return false;
   }

   if(!candidates ||
      !g_recovery_ok ||
      !g_storage_ok ||
      g_trade.PendingCount() > 0 ||
      !g_risk.TrailAttemptAllowed())
      return false;

   bool requested = false;

   for(int i = 0; i < ArraySize(tickets); i++)
   {
      if(g_trade.CloseTrailingPosition(tickets[i]))
         requested = true;
   }

   HD_ReconcileDeals(true);
   HD_SaveState();

   return requested;
}

bool HD_RunReHedgeHelper()
{
   if(!g_strategy.ReHedgeActive() ||
      !g_risk.CanReHedge() ||
      !g_recovery_ok ||
      !g_storage_ok)
      return false;

   if(g_strategy.HasReHedgeIntent())
   {
      if(!HD_ResolveReHedgeIntent())
      {
         g_recovery_ok = false;
         Print("[HedgeDrift][ERROR] Re-Hedge intent unresolved. ",
               "New entries blocked.");
      }

      HD_SaveState();
      return false;
   }

   ENUM_POSITION_TYPE side = POSITION_TYPE_BUY;

   if(!g_strategy.ReHedgeSignal(g_trade, side))
      return false;

   if(!HD_ReconcileDeals(true) ||
      g_trade.CountSide(side) > 0 ||
      g_trade.PendingCount() > 0)
      return false;

   g_strategy.BeginReHedgeIntent(side);

   if(!HD_SaveState())
   {
      // This invocation has not called the Trade Engine.
      g_strategy.SetReHedgeReceipt(true, 0, 0, 0);
      return false;
   }

   g_trade.OpenMissingSide(side, InpStartLot);

   bool no_execution = false;
   uint retcode = 0;
   ulong order_ticket = 0;
   ulong deal_ticket = 0;
   double requested_volume = 0.0;

   g_trade.GetOpeningReceipt(
      no_execution, retcode, order_ticket, deal_ticket,
      requested_volume
   );

   g_strategy.SetReHedgeReceipt(
      no_execution, retcode, order_ticket, deal_ticket,
      requested_volume
   );

   if(g_audit.Active())
   {
      g_audit.Record("RH_REQUEST_RECEIPT",
         "{\"side\":" + IntegerToString((int)side) +
         ",\"no_execution\":" + g_audit.Bool(no_execution) +
         ",\"retcode\":" + IntegerToString((int)retcode) +
         ",\"requested_volume\":" + g_audit.D(requested_volume) +
         ",\"order\":" + g_audit.U(order_ticket) +
         ",\"deal\":" + g_audit.U(deal_ticket) + "}",
         0, order_ticket, deal_ticket);
   }

   // Persist the receipt before clearing or resolving the intent.
   if(!HD_SaveState())
      return true;

   if(!HD_ResolveReHedgeIntent())
   {
      g_recovery_ok = false;
      Print("[HedgeDrift][ERROR] Replacement could not be registered. ",
            "Inspect terminal positions before continuing.");
   }

   HD_ReconcileDeals(true);
   HD_SaveState();
   return true;
}

void HD_RunPhase3()
{
   HD_ReconcileDeals(false);

   bool intent_ok = HD_ResolveReHedgeIntent();

   if(!intent_ok)
   {
      if(g_recovery_ok)
      {
         Print("[HedgeDrift][ERROR] Replacement intent mismatch. ",
               "New entries blocked; existing Risk Engine remains active.");
      }

      g_recovery_ok = false;
   }

   // Existing risk still runs even when new entries are blocked.
   bool risk_action = g_risk.Tick(g_trade, g_accounting);

   if(g_risk.Closing())
   {
      g_strategy.StopReHedge();
      HD_SaveState();
   }

   bool trailing_action = false;

   if(!risk_action)
      trailing_action = HD_RunTrailingHelper();

   if(!risk_action && !trailing_action && intent_ok)
      HD_RunReHedgeHelper();

   if(g_trade.Count() == 0)
   {
      if(g_hd.cycle == HD_ACTIVE || g_hd.cycle == HD_CLOSING)
         HD_SetCycle(HD_IDLE);
   }

   // Never start a new basket in the same pass as an RR close attempt.
   if(!risk_action &&
      !trailing_action &&
      !g_strategy.ReHedgeActive() &&
      g_recovery_ok &&
      g_storage_ok &&
      g_trade.PendingCount() == 0)
   {
      ENUM_TRADE_DIRECTION direction = DIR_BOTH;

      if(g_strategy.Signal(g_trade.Count(), direction))
         HD_OpenBasket(direction, false);
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

   g_initialized = false;
   g_recovery_ok = false;
   g_storage_ok = true;
   g_last_replay = 0;

   HD_InitRuntime();
   g_risk.Init();
   g_strategy.Init();

   // Audit failure does not determine EA initialization.
   g_audit.Init();

   if(!g_trade.Init(_Symbol, InpMagicNumber))
      return INIT_FAILED;

   if(!g_state.Init())
      return INIT_FAILED;

   if(!g_accounting.Init(_Symbol, InpMagicNumber, InpBaseCapital))
      return INIT_FAILED;

   if(g_trade.PendingCount() > 0)
   {
      Print("[HedgeDrift][ERROR] Outstanding EA orders detected. ",
            "Inspect terminal orders before restarting.");
      return INIT_FAILED;
   }

   if(g_state.Exists())
   {
      if(!g_state.Load())
         return INIT_FAILED;

      bool settings_match = g_state.SettingsMatch();

      if(!g_state.Good())
         return INIT_FAILED;

      if(g_trade.Count() > 0 && !settings_match)
      {
         Print("[HedgeDrift][ERROR] Inputs changed while a basket exists. ",
               "Restore the previous .set first.");
         return INIT_PARAMETERS_INCORRECT;
      }

      if(!HD_LoadRuntime(g_state) ||
         !g_accounting.LoadState(g_state) ||
         !g_risk.LoadState(g_state) ||
         !g_strategy.LoadState(g_state) ||
         !g_state.Good())
      {
         Print("[HedgeDrift][ERROR] Invalid state contents.");
         return INIT_FAILED;
      }

      if(!HD_ReconcileDeals(true))
         return INIT_FAILED;

      if(!HD_ResolveReHedgeIntent())
      {
         Print("[HedgeDrift][ERROR] Saved Re-Hedge intent mismatch.");
         return INIT_FAILED;
      }

      if(!g_risk.CoversLiveBasket())
      {
         Print("[HedgeDrift][ERROR] Live basket does not match saved risk. ",
               "No automatic recovery or new entries will be attempted.");
         return INIT_FAILED;
      }

      if(!settings_match)
      {
         // Flat basket: preserve money, apply the new strategy .set.
         HD_InitRuntime();
         g_risk.Init();
         g_strategy.Init();

         Print("[HedgeDrift][INFO] Flat recovery: new Inputs applied; ",
               "virtual accounting preserved.");
      }
      else
      {
         if(!g_state.Has("feature_version") &&
            InpEnableAutoReHedge &&
            g_trade.CountSide(POSITION_TYPE_BUY) == 1 &&
            g_trade.CountSide(POSITION_TYPE_SELL) == 1)
         {
            g_strategy.ArmReHedge();

            Print("[HedgeDrift][INFO] Legacy full hedge adopted. ",
                  "No historical missing-side timer was invented.");
         }

         Print("[HedgeDrift][INFO] Runtime settings restored from snapshot.");
      }
   }
   else
   {
      if(g_trade.Count() > 0)
      {
         Print("[HedgeDrift][ERROR] Existing basket without a saved state. ",
               "Cannot reconstruct original risk safely.");
         return INIT_FAILED;
      }

      Print("[HedgeDrift][INFO] Fresh virtual account.");
   }

   g_recovery_ok = true;

   if(!g_panel.Create())
   {
      Print("[HedgeDrift][ERROR] Panel creation failed.");
      return INIT_FAILED;
   }

   Comment("");

   if(g_accounting.PositionCount() > 0)
   {
      HD_SetCycle(HD_ACTIVE);

      Print("[HedgeDrift][INFO] Existing basket restored. ",
            "Original initial risk retained.");
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

   Print("[HedgeDrift][INFO] Phase 4: Manual / Timeout Hedge / Lock. ",
         "Persistence=", g_state.Enabled() ? "ON" : "OFF",
         " | Fixed StartLot.");

   g_initialized = true;

   if(!HD_SaveState())
   {
      g_initialized = false;
      return INIT_FAILED;
   }

   HD_UpdateDisplay();
   HD_AuditRuntime("RUN_READY", true);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();

   if(g_initialized && g_recovery_ok)
   {
      HD_ReconcileDeals(true);
      HD_SaveState();
   }

   if(g_audit.Active())
      HD_AuditRuntime("RUN_STOP_STATE", true);

   g_audit.Stop(reason);

   g_initialized = false;
   g_state.Close();
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
   if(!g_initialized)
      return;

   HD_ReconcileDeals(false);
   HD_SaveState();
   HD_UpdateDisplay();

   HD_AuditRuntime();
   g_audit.Pump();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   if(!g_initialized)
      return;

   if(HD_ReconcileDeals(true))
      HD_SaveState();

   HD_UpdateDisplay();
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

   if(g_audit.Active())
   {
      g_audit.Record("PANEL_ACTION",
         "{\"action\":" + g_audit.Q(EnumToString(action)) + "}");
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

            g_strategy.StopReHedge();
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

      HD_SaveState();
      HD_UpdateDisplay();
      HD_AuditRuntime("PANEL_STATE", true);
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
      g_strategy.StopReHedge();
      HD_SaveState();

      if(g_trade.Count() > 0)
      {
         g_risk.RequestClose();
         HD_SetCycle(HD_CLOSING);
         HD_SaveState();
      }

      g_trade.CloseAll();
      HD_ReconcileDeals(true);
      HD_SyncManualCycle();
   }
   else
   {
      if(g_trade.Count() > 0)
      {
         Print("[HedgeDrift][WARN] Open rejected: basket already active.");

         if(g_audit.Active())
         {
            g_audit.Record("MANUAL_BASKET_REJECT",
               "{\"buy_count\":" +
               IntegerToString(g_trade.CountSide(POSITION_TYPE_BUY)) +
               ",\"sell_count\":" +
               IntegerToString(g_trade.CountSide(POSITION_TYPE_SELL)) + "}",
               0, 0, 0, "WARN");
         }
      }
      else
      {
         ENUM_TRADE_DIRECTION direction = DIR_BUY_ONLY;

         if(action == HD_ACTION_SELL)
            direction = DIR_SELL_ONLY;
         else if(action == HD_ACTION_HEDGE)
            direction = DIR_HEDGE;

         HD_OpenBasket(direction, true);
      }
   }

   HD_ReconcileDeals(true);
   HD_SaveState();
   HD_UpdateDisplay();
   HD_AuditRuntime("PANEL_RESULT", true);
}