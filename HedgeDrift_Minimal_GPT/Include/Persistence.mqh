#ifndef HEDGEDRIFT_PERSISTENCE_MQH
#define HEDGEDRIFT_PERSISTENCE_MQH

#include "RuntimeState.mqh"

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
         return true;
      }

      if(ReadFile(m_path + ".bak"))
      {
         m_from_backup = true;
         Print("[HedgeDrift][WARN] Backup state loaded; history replay required.");
         return true;
      }

      m_ok = false;
      Print("[HedgeDrift][ERROR] No valid state snapshot.");
      return false;
   }

   string Settings()
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

      return Encode(value);
   }

   bool SettingsMatch()
   {
      return Get("settings") == Settings() && m_ok;
   }

   void Begin()
   {
      m_ok = true;
      m_body = "{\n";
      Put("schema", "1");
      Put("identity", m_identity);
      Put("settings", Settings());
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