#ifndef HEDGEDRIFT_PERSISTENCE_MQH
#define HEDGEDRIFT_PERSISTENCE_MQH

#include "RuntimeState.mqh"

#define HD_AUDIT_BUILD "03999bc+LeanAudit-v1"

struct HD_AuditGate
{
   bool used;
   string event;
   ulong ticket;
   ulong suppressed;
   datetime first_time;
   datetime last_time;
   ulong last_report;
};

class CHDLeanAudit
{
private:
   bool m_active;
   bool m_overflow_warned;
   int m_file;

   string m_run;
   string m_program;
   string m_folder;

   string m_rows[64];
   int m_head;
   int m_count;

   ulong m_sequence;
   ulong m_written;
   ulong m_dropped;
   ulong m_reported_dropped;

   ulong m_last_pump;
   ulong m_max_io_us;

   HD_AuditGate m_gates[8];

   ulong ClockMS()
   {
      if(MQLInfoInteger(MQL_TESTER))
         return (ulong)TimeCurrent() * (ulong)1000;

      return GetTickCount64();
   }

   uint Hash(const string text)
   {
      uint result = 2166136261;

      for(int i = 0; i < StringLen(text); i++)
      {
         result ^= (uint)StringGetCharacter(text, i);
         result *= 16777619;
      }

      return result;
   }

   string Csv(const string text)
   {
      string value = text;
      StringReplace(value, "\"", "\"\"");
      return "\"" + value + "\"";
   }

   bool WriteExact(const int handle, const string text)
   {
      uchar bytes[];
      int count = StringToCharArray(text, bytes, 0, WHOLE_ARRAY, CP_UTF8);

      if(count <= 0)
         return false;

      ResetLastError();
      uint written = FileWriteString(handle, text);
      int error = GetLastError();

      return error == 0 && written == (uint)(count - 1);
   }

   void Disable(const string reason)
   {
      if(m_file != INVALID_HANDLE)
      {
         FileClose(m_file);
         m_file = INVALID_HANDLE;
      }

      m_active = false;

      Print("[HedgeDrift][WARN] Audit disabled: ", reason,
            " Queued=", m_count,
            " Dropped=", m_dropped,
            ". Trading logic is not disabled by Audit.");

      m_count = 0;
   }

   void Summary(const int index)
   {
      if(!m_active || !m_gates[index].used ||
         m_gates[index].suppressed == 0)
         return;

      string detail =
         "{\"suppressed\":" + U(m_gates[index].suppressed) +
         ",\"first_server_time\":" +
         Q(TimeToString(m_gates[index].first_time,
                        TIME_DATE | TIME_SECONDS)) +
         ",\"last_server_time\":" +
         Q(TimeToString(m_gates[index].last_time,
                        TIME_DATE | TIME_SECONDS)) + "}";

      Record(m_gates[index].event + "_SUMMARY",
             detail, m_gates[index].ticket,
             0, 0, "INFO", m_gates[index].suppressed);

      m_gates[index].suppressed = 0;
      m_gates[index].last_report = ClockMS();
   }

   void AddConfig(string &body, const string key, const string value)
   {
      body += Q(key) + ":" + Q(value) + ",\r\n";
   }

   string Config()
   {
      string body = "{\r\n";

      AddConfig(body, "audit_build", HD_AUDIT_BUILD);
      AddConfig(body, "source_baseline",
         "03999bc1c9dd42a97cc3959acbd66e662b40fcbb");
      AddConfig(body, "run_id", m_run);
      AddConfig(body, "program", m_program);
      AddConfig(body, "symbol", _Symbol);
      AddConfig(body, "account_login",
         StringFormat("%I64d", AccountInfoInteger(ACCOUNT_LOGIN)));
      AddConfig(body, "account_server",
         AccountInfoString(ACCOUNT_SERVER));
      AddConfig(body, "account_currency",
         AccountInfoString(ACCOUNT_CURRENCY));
      AddConfig(body, "terminal_build",
         IntegerToString((int)TerminalInfoInteger(TERMINAL_BUILD)));
      AddConfig(body, "tester",
         MQLInfoInteger(MQL_TESTER) ? "true" : "false");

      AddConfig(body, "InpEnableAutoLot", Bool(InpEnableAutoLot));
      AddConfig(body, "InpBaseCapital", DoubleToString(InpBaseCapital, 16));
      AddConfig(body, "InpStartLot", DoubleToString(InpStartLot, 16));
      AddConfig(body, "InpStepCapital", DoubleToString(InpStepCapital, 16));
      AddConfig(body, "InpStepLot", DoubleToString(InpStepLot, 16));
      AddConfig(body, "InpRefillAmount", DoubleToString(InpRefillAmount, 16));
      AddConfig(body, "InpEnableHardCutLoss", Bool(InpEnableHardCutLoss));
      AddConfig(body, "InpCutLossPoints", IntegerToString(InpCutLossPoints));
      AddConfig(body, "InpStrategyMode", IntegerToString((int)InpStrategyMode));
      AddConfig(body, "InpTradeDirection", IntegerToString((int)InpTradeDirection));
      AddConfig(body, "InpEnableHedgeTriggerLock", Bool(InpEnableHedgeTriggerLock));
      AddConfig(body, "InpLockDistancePoints", IntegerToString(InpLockDistancePoints));
      AddConfig(body, "InpEnableCutLossReLock", Bool(InpEnableCutLossReLock));
      AddConfig(body, "InpEnableAutoNewCycle", Bool(InpEnableAutoNewCycle));
      AddConfig(body, "InpEnableCycleTimeout", Bool(InpEnableCycleTimeout));
      AddConfig(body, "InpTimeoutSeconds", IntegerToString(InpTimeoutSeconds));
      AddConfig(body, "InpEnableAutoBE", Bool(InpEnableAutoBE));
      AddConfig(body, "InpBETriggerPoints", IntegerToString(InpBETriggerPoints));
      AddConfig(body, "InpBELockPercent", DoubleToString(InpBELockPercent, 16));
      AddConfig(body, "InpBEType", IntegerToString((int)InpBEType));
      AddConfig(body, "InpEnableRRTarget", Bool(InpEnableRRTarget));
      AddConfig(body, "InpRRTargetPercent", DoubleToString(InpRRTargetPercent, 16));
      AddConfig(body, "InpEnableTrailingTP", Bool(InpEnableTrailingTP));
      AddConfig(body, "InpTrailingStepPoints", IntegerToString(InpTrailingStepPoints));
      AddConfig(body, "InpEnableAutoReHedge", Bool(InpEnableAutoReHedge));
      AddConfig(body, "InpEnableSessionFilter", Bool(InpEnableSessionFilter));
      AddConfig(body, "InpEnableSession1", Bool(InpEnableSession1));
      AddConfig(body, "InpSession1Time", InpSession1Time);
      AddConfig(body, "InpEnableSession2", Bool(InpEnableSession2));
      AddConfig(body, "InpSession2Time", InpSession2Time);
      AddConfig(body, "InpEnableSession3", Bool(InpEnableSession3));
      AddConfig(body, "InpSession3Time", InpSession3Time);
      AddConfig(body, "InpEnableAuditLog", Bool(InpEnableAuditLog));
      AddConfig(body, "InpEnablePersistence", Bool(InpEnablePersistence));
      AddConfig(body, "InpPersistenceInTester", Bool(InpPersistenceInTester));
      AddConfig(body, "InpMagicNumber", U(InpMagicNumber));

      body += "\"complete\":true\r\n}\r\n";
      return body;
   }

public:
   CHDLeanAudit()
   {
      m_active = false;
      m_overflow_warned = false;
      m_file = INVALID_HANDLE;
      m_head = 0;
      m_count = 0;
      m_sequence = 0;
      m_written = 0;
      m_dropped = 0;
      m_reported_dropped = 0;
      m_last_pump = 0;
      m_max_io_us = 0;
      m_run = "";
      m_program = "";
      m_folder = "";

      for(int i = 0; i < 8; i++)
      {
         m_gates[i].used = false;
         m_gates[i].suppressed = 0;
      }
   }

   bool Active()
   {
      return m_active;
   }

   string Q(const string text)
   {
      string value = text;
      StringReplace(value, "\\", "\\\\");
      StringReplace(value, "\"", "\\\"");
      StringReplace(value, "\r", "\\r");
      StringReplace(value, "\n", "\\n");
      StringReplace(value, "\t", "\\t");
      return "\"" + value + "\"";
   }

   string D(const double value)
   {
      if(!MathIsValidNumber(value))
         return "null";

      return DoubleToString(value, 10);
   }

   string U(const ulong value)
   {
      return StringFormat("%I64u", value);
   }

   string Bool(const bool value)
   {
      return value ? "true" : "false";
   }

   void Init()
   {
      if(!InpEnableAuditLog)
         return;

      m_program = MQLInfoString(MQL_PROGRAM_NAME);

      m_run = TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS);
      StringReplace(m_run, ".", "-");
      StringReplace(m_run, ":", "-");
      StringReplace(m_run, " ", "_");

      m_run += "_" + U(GetTickCount64()) + "_" +
               StringFormat("%I64d", ChartID());

      string identity =
         StringFormat("%I64d", AccountInfoInteger(ACCOUNT_LOGIN)) + "_" +
         IntegerToString((long)Hash(AccountInfoString(ACCOUNT_SERVER))) + "_" +
         IntegerToString((long)Hash(_Symbol)) + "_" + U(InpMagicNumber);

      string root = "HedgeDrift\\Audit";
      string owner = root + "\\" + identity;
      m_folder = owner + "\\" + m_run;

      FolderCreate("HedgeDrift");
      FolderCreate(root);
      FolderCreate(owner);
      FolderCreate(m_folder);

      if(FileIsExist(m_folder + "\\config.json") ||
         FileIsExist(m_folder + "\\events.csv"))
      {
         Disable("Run path collision");
         return;
      }

      int config_file = FileOpen(
         m_folder + "\\config.json",
         FILE_WRITE | FILE_TXT | FILE_ANSI, 0, CP_UTF8
      );

      if(config_file == INVALID_HANDLE)
      {
         Disable("Cannot open config.json");
         return;
      }

      bool config_ok = WriteExact(config_file, Config());
      ResetLastError();
      FileFlush(config_file);

      if(GetLastError() != 0)
         config_ok = false;

      FileClose(config_file);

      if(!config_ok)
      {
         Disable("Cannot finish config.json");
         return;
      }

      m_file = FileOpen(
         m_folder + "\\events.csv",
         FILE_WRITE | FILE_TXT | FILE_ANSI |
         FILE_SHARE_READ,
         0, CP_UTF8
      );

      if(m_file == INVALID_HANDLE)
      {
         Disable("Cannot open events.csv");
         return;
      }

      string header =
         "run_id,seq,server_time,mono_us,event,level,program,symbol,magic,"
         "cycle,mode,position_ticket,order_id,deal_id,repeat_count,details_json\r\n";

      if(!WriteExact(m_file, header))
      {
         Disable("Cannot write CSV header");
         return;
      }

      m_active = true;
      m_last_pump = ClockMS();

      Record("RUN_START",
         "{\"audit_build\":" + Q(HD_AUDIT_BUILD) +
         ",\"clock\":" +
         Q(MQLInfoInteger(MQL_TESTER) ? "tester_server_time" : "monotonic") +
         "}");

      Print("[HedgeDrift][INFO] Lean Audit ON: MQL5\\Files\\", m_folder);
   }

   void Record(const string event,
               const string details = "{}",
               const ulong ticket = 0,
               const ulong order = 0,
               const ulong deal = 0,
               const string level = "INFO",
               const ulong repeats = 0)
   {
      if(!m_active)
         return;

      m_sequence++;

      if(m_count >= 64 || StringLen(details) > 2048)
      {
         m_dropped++;

         if(!m_overflow_warned)
         {
            m_overflow_warned = true;
            Print("[HedgeDrift][WARN] Audit data loss: queue/full or oversized row. ",
                  "Do not treat this run as complete evidence.");
         }

         return;
      }

      string row =
         Csv(m_run) + "," +
         U(m_sequence) + "," +
         Csv(TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS)) + "," +
         U(GetMicrosecondCount()) + "," +
         Csv(event) + "," +
         Csv(level) + "," +
         Csv(m_program) + "," +
         Csv(_Symbol) + "," +
         U(InpMagicNumber) + "," +
         Csv(HD_CycleName(g_hd.cycle)) + "," +
         IntegerToString((int)g_hd.strategy) + "," +
         U(ticket) + "," + U(order) + "," + U(deal) + "," +
         U(repeats) + "," + Csv(details) + "\r\n";

      int tail = (m_head + m_count) % 64;
      m_rows[tail] = row;
      m_count++;
   }

   bool Gate(const string event, const ulong ticket = 0)
   {
      if(!m_active)
         return false;

      int empty = -1;
      int oldest = 0;

      for(int i = 0; i < 8; i++)
      {
         if(m_gates[i].used &&
            m_gates[i].event == event &&
            m_gates[i].ticket == ticket)
         {
            m_gates[i].suppressed++;
            m_gates[i].last_time = TimeCurrent();
            return false;
         }

         if(!m_gates[i].used && empty < 0)
            empty = i;

         if(m_gates[i].last_report < m_gates[oldest].last_report)
            oldest = i;
      }

      int slot = empty >= 0 ? empty : oldest;

      if(m_gates[slot].used)
         Summary(slot);

      m_gates[slot].used = true;
      m_gates[slot].event = event;
      m_gates[slot].ticket = ticket;
      m_gates[slot].suppressed = 0;
      m_gates[slot].first_time = TimeCurrent();
      m_gates[slot].last_time = TimeCurrent();
      m_gates[slot].last_report = ClockMS();

      return true;
   }

   void ClearGate(const string event, const ulong ticket = 0)
   {
      if(!m_active)
         return;

      for(int i = 0; i < 8; i++)
      {
         if(m_gates[i].used &&
            m_gates[i].event == event &&
            m_gates[i].ticket == ticket)
         {
            Summary(i);
            m_gates[i].used = false;
         }
      }
   }

   void Pump(const bool force = false)
   {
      if(!m_active)
         return;

      ulong now = ClockMS();

      if(!force && now - m_last_pump < 5000)
         return;

      m_last_pump = now;

      for(int i = 0; i < 8; i++)
      {
         if(m_gates[i].used &&
            (force || now - m_gates[i].last_report >= 30000))
            Summary(i);
      }

      ulong start = GetMicrosecondCount();
      int limit = force ? 64 : 16;
      int done = 0;

      while(m_count > 0 && done < limit)
      {
         if(!force && done > 0 &&
            GetMicrosecondCount() - start >= 2000)
            break;

         string row = m_rows[m_head];

         // Conservative reserve for UTF-8 and the closing records.
         if(FileSize(m_file) + (ulong)StringLen(row) * 4 >
            (ulong)10485760)
         {
            Disable("10 MB event-file limit reached");
            return;
         }

         if(!WriteExact(m_file, row))
         {
            Disable("CSV write failed");
            return;
         }

         m_rows[m_head] = "";
         m_head = (m_head + 1) % 64;
         m_count--;
         m_written++;
         done++;
      }

      if(done > 0)
      {
         ResetLastError();
         FileFlush(m_file);

         if(GetLastError() != 0)
         {
            Disable("CSV flush failed");
            return;
         }
      }

      ulong duration = GetMicrosecondCount() - start;

      if(duration > m_max_io_us)
         m_max_io_us = duration;

      if(m_dropped != m_reported_dropped && m_count < 64)
      {
         Record("AUDIT_DATA_LOSS",
            "{\"dropped_total\":" + U(m_dropped) + "}",
            0, 0, 0, "WARN");

         m_reported_dropped = m_dropped;
      }
   }

   void Stop(const int reason)
   {
      if(!m_active)
         return;

      Pump(true);

      if(!m_active)
         return;

      Record("RUN_END",
         "{\"deinit_reason\":" + IntegerToString(reason) +
         ",\"written_before_end\":" + U(m_written) +
         ",\"dropped\":" + U(m_dropped) +
         ",\"max_io_us\":" + U(m_max_io_us) +
         ",\"incomplete\":" + Bool(m_dropped > 0) + "}");

      Pump(true);

      if(m_file != INVALID_HANDLE)
      {
         FileClose(m_file);
         m_file = INVALID_HANDLE;
      }

      m_active = false;
   }
};

CHDLeanAudit g_audit;

class CHDPersistence
{
private:
   string m_path;
   string m_identity;
   string m_body;
   string m_read;
   string m_last_body;
   bool m_enabled;
   bool m_ok;
   bool m_from_backup;
   int m_lock;

   uint Hash(const string value)
   {
      uint hash = 2166136261;

      for(int i = 0; i < StringLen(value); i++)
      {
         hash ^= (uint)StringGetCharacter(value, i);
         hash *= 16777619;
      }

      return hash;
   }

   string Encode(const string value)
   {
      string result = "";

      for(int i = 0; i < StringLen(value); i++)
      {
         if(i > 0)
            result += "_";

         result += IntegerToString(
            (int)StringGetCharacter(value, i)
         );
      }

      return result;
   }

   bool ReadFile(const string path)
   {
      int handle = FileOpen(
         path, FILE_READ | FILE_TXT | FILE_ANSI, 0, CP_UTF8
      );

      if(handle == INVALID_HANDLE)
         return false;

      if(FileSize(handle) > 67108864)
      {
         FileClose(handle);
         return false;
      }

      string text = "";

      while(!FileIsEnding(handle))
         text += FileReadString(handle) + "\n";

      FileClose(handle);

      string marker = "\"checksum\":\"";
      int index = StringFind(text, marker);

      if(index < 0 ||
         StringFind(text, marker, index + 1) >= 0)
         return false;

      string prefix = StringSubstr(text, 0, index);

      m_read = text;
      m_ok = true;

      ulong expected = U("checksum");

      string tail =
         "\"checksum\":\"" + StringFormat("%I64u", expected) +
         "\",\n\"complete\":\"1\"\n}\n";

      if(!m_ok ||
         expected != (ulong)Hash(prefix) ||
         StringSubstr(text, index) != tail)
         return false;

      if(Get("schema") != "1" ||
         Get("identity") != m_identity ||
         !m_ok)
         return false;

      m_last_body = prefix;
      return true;
   }

public:
   CHDPersistence()
   {
      m_lock = INVALID_HANDLE;
      m_enabled = false;
      m_ok = true;
      m_from_backup = false;
      m_path = "";
      m_identity = "";
      m_body = "";
      m_read = "";
      m_last_body = "";
   }

   bool Init()
   {
      m_enabled =
         InpEnablePersistence &&
         (!MQLInfoInteger(MQL_TESTER) || InpPersistenceInTester);

      m_ok = true;
      m_from_backup = false;

      string identity =
         AccountInfoString(ACCOUNT_SERVER) + "|" +
         StringFormat("%I64d", AccountInfoInteger(ACCOUNT_LOGIN)) + "|" +
         _Symbol + "|" + StringFormat("%I64u", InpMagicNumber);

      m_identity = Encode(identity);

      string folder =
         "HedgeDrift\\" +
         StringFormat("%I64d", AccountInfoInteger(ACCOUNT_LOGIN)) + "_" +
         IntegerToString((long)Hash(AccountInfoString(ACCOUNT_SERVER))) + "_" +
         IntegerToString((long)Hash(_Symbol)) + "_" +
         StringFormat("%I64u", InpMagicNumber);

      m_path = folder + "\\state.json";

      if(!m_enabled)
         return true;

      FolderCreate("HedgeDrift");
      FolderCreate(folder);

      // No FILE_SHARE flags: one owner for this state identity.
      m_lock = FileOpen(
         folder + "\\state.lock",
         FILE_READ | FILE_WRITE | FILE_BIN
      );

      if(m_lock == INVALID_HANDLE)
      {
         Print("[HedgeDrift][ERROR] State lock unavailable. ",
               "Check path or another EA using the same identity.");
         return false;
      }

      Print("[HedgeDrift][INFO] State file: MQL5\\Files\\", m_path);
      return true;
   }

   void Close()
   {
      if(m_lock != INVALID_HANDLE)
      {
         FileClose(m_lock);
         m_lock = INVALID_HANDLE;
      }
   }

   bool Enabled()
   {
      return m_enabled;
   }

   bool Exists()
   {
      return m_enabled &&
         (FileIsExist(m_path) || FileIsExist(m_path + ".bak"));
   }

   bool Load()
   {
      if(!m_enabled)
         return false;

      if(ReadFile(m_path))
      {
         m_from_backup = false;
         Print("[HedgeDrift][INFO] Main state loaded.");

         if(g_audit.Active())
            g_audit.Record("STATE_LOADED", "{\"source\":\"main\"}");

         return true;
      }

      if(ReadFile(m_path + ".bak"))
      {
         m_from_backup = true;
         Print("[HedgeDrift][WARN] Backup state loaded; history replay required.");

         if(g_audit.Active())
            g_audit.Record("STATE_LOADED",
               "{\"source\":\"backup\",\"replay_required\":true}",
               0, 0, 0, "WARN");

         return true;
      }

      m_ok = false;
      Print("[HedgeDrift][ERROR] No valid state snapshot.");

      if(g_audit.Active())
         g_audit.Record("STATE_LOAD_FAILED", "{}",
                        0, 0, 0, "ERROR");

      return false;
   }

   string Settings(const bool include_features = true)
   {
      string value =
         DoubleToString(InpBaseCapital, 16) + "|" +
         DoubleToString(InpStartLot, 16) + "|" +
         DoubleToString(InpStepCapital, 16) + "|" +
         DoubleToString(InpStepLot, 16) + "|" +
         DoubleToString(InpRefillAmount, 16) + "|" +
         IntegerToString(InpCutLossPoints) + "|" +
         IntegerToString(InpLockDistancePoints) + "|" +
         IntegerToString(InpTimeoutSeconds) + "|" +
         IntegerToString(InpBETriggerPoints) + "|" +
         DoubleToString(InpBELockPercent, 16) + "|" +
         DoubleToString(InpRRTargetPercent, 16) + "|" +
         InpSession1Time + "|" + InpSession2Time + "|" + InpSession3Time;

      int flags[] =
      {
         (int)InpStrategyMode,
         (int)InpTradeDirection,
         (int)InpBEType,
         (int)InpEnableAutoLot,
         (int)InpEnableHardCutLoss,
         (int)InpEnableHedgeTriggerLock,
         (int)InpEnableCutLossReLock,
         (int)InpEnableAutoNewCycle,
         (int)InpEnableCycleTimeout,
         (int)InpEnableAutoBE,
         (int)InpEnableRRTarget,
         (int)InpEnableSessionFilter,
         (int)InpEnableSession1,
         (int)InpEnableSession2,
         (int)InpEnableSession3
      };

      for(int i = 0; i < ArraySize(flags); i++)
         value += "|" + IntegerToString(flags[i]);

      if(include_features)
      {
         value += "|" + IntegerToString((int)InpEnableTrailingTP);
         value += "|" + IntegerToString(InpTrailingStepPoints);
         value += "|" + IntegerToString((int)InpEnableAutoReHedge);
      }

      return Encode(value);
   }

   bool Has(const string key)
   {
      string marker = "\"" + key + "\":\"";
      return StringFind(m_read, marker) >= 0;
   }

   bool SettingsMatch()
   {
      string saved = Get("settings");

      if(!m_ok)
         return false;

      if(saved == Settings())
         return true;

      // Snapshot from Phase 4 before these feature inputs existed.
      return !Has("feature_version") && saved == Settings(false);
   }

   void Begin()
   {
      m_ok = true;
      m_body = "{\n";
      Put("schema", "1");
      Put("identity", m_identity);
      Put("settings", Settings());
      PutU("feature_version", 1);
   }

   void Put(const string key, const string value)
   {
      if(StringFind(value, "\"") >= 0 ||
         StringFind(value, "\\") >= 0 ||
         StringFind(value, "\n") >= 0 ||
         StringFind(value, "\r") >= 0)
      {
         m_ok = false;
         return;
      }

      m_body += "\"" + key + "\":\"" + value + "\",\n";
   }

   void PutU(const string key, const ulong value)
   {
      Put(key, StringFormat("%I64u", value));
   }

   void PutD(const string key, const double value)
   {
      if(!MathIsValidNumber(value))
      {
         m_ok = false;
         return;
      }

      Put(key, DoubleToString(value, 16));
   }

   void PutIds(const string key, const ulong &values[])
   {
      string text = "";

      for(int i = 0; i < ArraySize(values); i++)
      {
         if(i > 0)
            text += ",";

         text += StringFormat("%I64u", values[i]);
      }

      Put(key, text);
   }

   string Get(const string key)
   {
      string marker = "\"" + key + "\":\"";
      int start = StringFind(m_read, marker);

      if(start < 0 ||
         StringFind(m_read, marker, start + 1) >= 0)
      {
         m_ok = false;
         return "";
      }

      start += StringLen(marker);
      int end = StringFind(m_read, "\"", start);

      if(end < 0)
      {
         m_ok = false;
         return "";
      }

      return StringSubstr(m_read, start, end - start);
   }

   bool ParseU(const string text, ulong &value)
   {
      value = 0;

      if(StringLen(text) == 0)
      {
         m_ok = false;
         return false;
      }

      for(int i = 0; i < StringLen(text); i++)
      {
         ushort character = StringGetCharacter(text, i);

         if(character < 48 || character > 57)
         {
            m_ok = false;
            return false;
         }

         ulong digit = (ulong)(character - 48);

         if(value > (ULONG_MAX - digit) / (ulong)10)
         {
            m_ok = false;
            return false;
         }

         value = value * (ulong)10 + digit;
      }

      return true;
   }

   ulong U(const string key)
   {
      ulong result = 0;
      ParseU(Get(key), result);
      return result;
   }

   int I(const string key)
   {
      ulong value = U(key);

      if(value > 2147483647)
      {
         m_ok = false;
         return 0;
      }

      return (int)value;
   }

   bool B(const string key)
   {
      ulong value = U(key);

      if(value > 1)
         m_ok = false;

      return value == 1;
   }

   double D(const string key)
   {
      string text = Get(key);
      int digits = 0;
      int dots = 0;

      for(int i = 0; i < StringLen(text); i++)
      {
         ushort c = StringGetCharacter(text, i);

         if(c >= 48 && c <= 57)
            digits++;
         else if(c == 46)
            dots++;
         else if(!(c == 45 && i == 0))
            m_ok = false;
      }

      if(digits == 0 || dots > 1)
         m_ok = false;

      double value = StringToDouble(text);

      if(!MathIsValidNumber(value))
         m_ok = false;

      return value;
   }

   bool Ids(const string key, ulong &values[])
   {
      string text = Get(key);
      ArrayResize(values, 0);

      if(!m_ok)
         return false;

      if(text == "")
         return true;

      string parts[];
      int count = StringSplit(text, ',', parts);

      if(count <= 0 || count > 200000 ||
         ArrayResize(values, count) != count)
      {
         m_ok = false;
         return false;
      }

      for(int i = 0; i < count; i++)
      {
         ulong value = 0;

         if(!ParseU(parts[i], value))
            return false;

         values[i] = value;
      }

      return m_ok;
   }

   bool Good()
   {
      return m_ok;
   }

   bool Commit()
   {
      if(!m_enabled)
         return true;

      if(!m_ok)
         return false;

      if(m_body == m_last_body && !m_from_backup)
         return true;

      string text =
         m_body +
         "\"checksum\":\"" +
         IntegerToString((long)Hash(m_body)) +
         "\",\n\"complete\":\"1\"\n}\n";

      string temp = m_path + ".tmp";

      int handle = FileOpen(
         temp, FILE_WRITE | FILE_TXT | FILE_ANSI, 0, CP_UTF8
      );

      if(handle == INVALID_HANDLE)
         return false;

      ResetLastError();
      uint written = FileWriteString(handle, text);
      FileFlush(handle);
      int error = GetLastError();
      FileClose(handle);

      if(written == 0 || error != 0)
         return false;

      // Do not replace a valid backup with an invalid main file.
      if(!m_from_backup && FileIsExist(m_path))
      {
         if(!FileCopy(m_path, 0, m_path + ".bak", FILE_REWRITE))
            return false;
      }

      if(!FileMove(temp, 0, m_path, FILE_REWRITE))
         return false;

      m_last_body = m_body;
      m_from_backup = false;
      return true;
   }
};

void HD_SaveRuntime(CHDPersistence &state)
{
   state.PutU("rt_cycle", (ulong)g_hd.cycle);
   state.PutU("rt_strategy", (ulong)g_hd.strategy);
   state.PutU("rt_direction", (ulong)g_hd.direction);
   state.PutU("rt_be_type", (ulong)g_hd.be_type);
   state.PutD("rt_lock", g_hd.lock_price);
   state.PutU("rt_since", (ulong)g_hd.state_since);

   ulong flags[] =
   {
      (ulong)g_hd.auto_lot,
      (ulong)g_hd.hard_cut_loss,
      (ulong)g_hd.hedge_trigger_lock,
      (ulong)g_hd.cut_loss_relock,
      (ulong)g_hd.auto_new_cycle,
      (ulong)g_hd.cycle_timeout,
      (ulong)g_hd.auto_be,
      (ulong)g_hd.rr_target,
      (ulong)g_hd.session_filter,
      (ulong)g_hd.session1,
      (ulong)g_hd.session2,
      (ulong)g_hd.session3
   };

   state.PutIds("rt_flags", flags);
}

bool HD_LoadRuntime(CHDPersistence &state)
{
   int cycle = state.I("rt_cycle");
   int strategy = state.I("rt_strategy");
   int direction = state.I("rt_direction");
   int be_type = state.I("rt_be_type");

   double lock_price = state.D("rt_lock");
   ulong since = state.U("rt_since");

   ulong flags[];

   if(!state.Ids("rt_flags", flags) ||
      ArraySize(flags) != 12)
      return false;

   for(int i = 0; i < ArraySize(flags); i++)
      if(flags[i] > 1)
         return false;

   if(!state.Good() ||
      cycle > (int)HD_CLOSING ||
      strategy > 2 || direction > 3 || be_type > 1 ||
      lock_price < 0.0)
      return false;

   g_hd.cycle = (ENUM_HD_CYCLE_STATE)cycle;
   g_hd.strategy = (ENUM_STRATEGY_MODE)strategy;
   g_hd.direction = (ENUM_TRADE_DIRECTION)direction;
   g_hd.be_type = (ENUM_BE_TYPE)be_type;
   g_hd.lock_price = lock_price;
   g_hd.state_since = (datetime)since;

   g_hd.auto_lot = flags[0] == 1;
   g_hd.hard_cut_loss = flags[1] == 1;
   g_hd.hedge_trigger_lock = flags[2] == 1;
   g_hd.cut_loss_relock = flags[3] == 1;
   g_hd.auto_new_cycle = flags[4] == 1;
   g_hd.cycle_timeout = flags[5] == 1;
   g_hd.auto_be = flags[6] == 1;
   g_hd.rr_target = flags[7] == 1;
   g_hd.session_filter = flags[8] == 1;
   g_hd.session1 = flags[9] == 1;
   g_hd.session2 = flags[10] == 1;
   g_hd.session3 = flags[11] == 1;

   return true;
}

#endif