#ifndef HEDGEDRIFT_CONFIG_MQH
#define HEDGEDRIFT_CONFIG_MQH

#define HD_VERSION "v2.1"

enum ENUM_STRATEGY_MODE
{
   MODE_TIMEOUT_HEDGE = 0,
   MODE_LOCK_PRICE   = 1,
   MODE_MANUAL_FREE  = 2
};

enum ENUM_TRADE_DIRECTION
{
   DIR_BUY_ONLY  = 0,
   DIR_SELL_ONLY = 1,
   DIR_BOTH      = 2,
   DIR_HEDGE     = 3
};

enum ENUM_BE_TYPE
{
   BE_TYPE_FIXED   = 0,
   BE_TYPE_DYNAMIC = 1
};

input group "ทุนจำลอง / Auto Lot"
input bool   InpEnableAutoLot = true;  // สวิตช์ Auto-Lot (รุ่นนี้ยังใช้ StartLot)
input double InpBaseCapital  = 50.0;   // ทุนจำลองตั้งต้น (สกุลเงินบัญชี)
input double InpStartLot     = 0.01;   // ขนาด Lot ที่ใช้เปิดจริงในรุ่นนี้
input double InpStepCapital  = 50.0;   // ขั้นทุนสำหรับ Auto-Lot (ยังไม่เชื่อม Execution)
input double InpStepLot      = 0.01;   // ขั้น Lot สำหรับ Auto-Lot (ยังไม่เชื่อม Execution)
input double InpRefillAmount = 10.0;   // จำนวนทุนจำลองที่เพิ่มต่อการกด Refill

input group "ควบคุมความเสี่ยง / Hard SL"
input bool InpEnableHardCutLoss = true; // เปิด Hard SL บน Server เมื่อออกไม้ใหม่
input int  InpCutLossPoints     = 1000; // ระยะ Hard SL และอ้างอิง RR (Points)

input group "กลยุทธ์ / ทิศทาง / Lock"
input ENUM_STRATEGY_MODE   InpStrategyMode   = MODE_LOCK_PRICE; // โหมดหลัก: Timeout Hedge / Lock / Manual
input ENUM_TRADE_DIRECTION InpTradeDirection = DIR_BOTH;        // ทิศทาง Lock: BUY / SELL / BOTH / HEDGE

input bool InpEnableHedgeTriggerLock = true; // เปิดการจับสัญญาณข้ามระดับ Lock
input int  InpLockDistancePoints     = 1000; // ระยะ Trigger จาก Lock Price (Points)
input bool InpEnableCutLossReLock    = true; // ตั้ง Lock ใหม่จาก Hard SL เดิมใน Lock Mode

input group "รอบอัตโนมัติ / Timeout"
input bool InpEnableAutoNewCycle = true; // เริ่มรอบทั่วไปใหม่อัตโนมัติเมื่อ Basket จบ
input bool InpEnableCycleTimeout = true; // เปิด Timer ของ Timeout Mode ไม่ใช่ Re-Hedge
input int  InpTimeoutSeconds     = 300;  // เวลารอ Timeout และเติมขา Re-Hedge (วินาที)

input group "ป้องกันกำไร / BE / RR / Trailing"
input bool         InpEnableAutoBE    = true;          // เปิดการเลื่อน SL แบบ Fixed หรือ Dynamic BE
input int          InpBETriggerPoints = 1000;          // กำไรเป็น Points ก่อนเริ่ม BE
input double       InpBELockPercent   = 20.0;          // สัดส่วนระยะกำไรที่ล็อกด้วย BE (%)
input ENUM_BE_TYPE InpBEType          = BE_TYPE_FIXED; // รูปแบบ BE: FIXED คงที่ / DYNAMIC ตามราคา

input bool   InpEnableRRTarget  = true;  // ปิด Basket เมื่อกำไรลอยตัวถึงเป้า RR
input double InpRRTargetPercent = 100.0; // เป้าเป็น % ของ Initial Risk ไม่ใช่ % ทุน

input bool InpEnableTrailingTP   = false; // ปิดรายไม้เมื่อย้อนจาก Peak และ Profit > 0
input int  InpTrailingStepPoints = 500;   // ระยะย้อนจาก Peak ไม่ใช่ระยะเลื่อน SL (Points)
input bool InpEnableAutoReHedge  = true;  // เติมฝั่งที่หายหลัง Timeout เฉพาะรอบ Hedge

input group "ช่วงเวลา Lock / เวลา Server"
input bool   InpEnableSessionFilter = true;          // กรองเวลาเฉพาะ Lock ไม่บล็อก Manual/Re-Hedge
input bool   InpEnableSession1      = true;          // เปิดช่วงเวลาเทรด Lock ช่วงที่ 1
input string InpSession1Time        = "01:30-05:00"; // ช่วงที่ 1 เวลา Server รูปแบบ HH:MM-HH:MM
input bool   InpEnableSession2      = true;          // เปิดช่วงเวลาเทรด Lock ช่วงที่ 2
input string InpSession2Time        = "10:00-14:00"; // ช่วงที่ 2 เวลา Server รูปแบบ HH:MM-HH:MM
input bool   InpEnableSession3      = true;          // เปิดช่วงเวลาเทรด Lock ช่วงที่ 3
input string InpSession3Time        = "21:00-24:00"; // ช่วงที่ 3 เวลา Server รองรับสิ้นสุด 24:00

input group "บันทึกและกู้สถานะ / Persistence"
input bool InpEnablePersistence = true;       // บันทึกและกู้ State ที่เก็บไว้แล้ว
input bool InpPersistenceInTester = false;    // อนุญาต Persistence ใน Tester (ปกติปิด)

input group "ตัวตน EA / Identity"
input ulong InpMagicNumber = 998874;          // รหัสเจ้าของสถานะและไฟล์ State ของ EA

string HD_OrderComment()
{
   return "HedgeDrift_RR1:"
          + DoubleToString(InpRRTargetPercent / 100.0, 2);
}

bool HD_ParseClock(const string value,
                   const bool allow_midnight_end,
                   int &minutes)
{
   if(StringLen(value) != 5 ||
      StringSubstr(value, 2, 1) != ":")
      return false;

   for(int i = 0; i < 5; i++)
   {
      if(i == 2)
         continue;

      ushort character = StringGetCharacter(value, i);
      if(character < 48 || character > 57)
         return false;
   }

   int hour   = (int)StringToInteger(StringSubstr(value, 0, 2));
   int minute = (int)StringToInteger(StringSubstr(value, 3, 2));

   if(hour == 24 && minute == 0 && allow_midnight_end)
   {
      minutes = 1440;
      return true;
   }

   if(hour < 0 || hour > 23 || minute < 0 || minute > 59)
      return false;

   minutes = hour * 60 + minute;
   return true;
}

bool HD_ValidSession(const string value)
{
   if(StringLen(value) != 11 ||
      StringSubstr(value, 5, 1) != "-")
      return false;

   int start_minutes = 0;
   int end_minutes   = 0;

   if(!HD_ParseClock(StringSubstr(value, 0, 5),
                     false, start_minutes))
      return false;

   if(!HD_ParseClock(StringSubstr(value, 6, 5),
                     true, end_minutes))
      return false;

   return start_minutes != end_minutes;
}

bool HD_ConfigError(const string message)
{
   Print("[HedgeDrift][ERROR] Config: ", message);
   return false;
}

bool HD_ValidateConfig()
{
   if(InpBaseCapital <= 0.0)
      return HD_ConfigError("BaseCapital must be positive.");

   if(InpStartLot <= 0.0)
      return HD_ConfigError("StartLot must be positive.");

   if(InpRefillAmount <= 0.0)
      return HD_ConfigError("RefillAmount must be positive.");

   if(InpEnableAutoLot &&
      (InpStepCapital <= 0.0 || InpStepLot <= 0.0))
      return HD_ConfigError("AutoLot steps must be positive.");

   if(InpEnableHardCutLoss && InpCutLossPoints <= 0)
      return HD_ConfigError("CutLossPoints must be positive.");

   if(InpEnableHedgeTriggerLock && InpLockDistancePoints <= 0)
      return HD_ConfigError("LockDistancePoints must be positive.");

   if(InpEnableCycleTimeout && InpTimeoutSeconds <= 0)
      return HD_ConfigError("TimeoutSeconds must be positive.");

   if(InpEnableAutoBE &&
      (InpBETriggerPoints <= 0 ||
       InpBELockPercent <= 0.0 ||
       InpBELockPercent >= 100.0))
      return HD_ConfigError("Invalid BE trigger or lock percent.");

   if(InpEnableRRTarget &&
      (InpRRTargetPercent <= 0.0 || InpCutLossPoints <= 0))
      return HD_ConfigError("RR requires positive target and risk distance.");

   if(InpEnableTrailingTP && InpTrailingStepPoints <= 0)
      return HD_ConfigError("TrailingStepPoints must be positive.");

   if(InpEnableAutoReHedge && InpTimeoutSeconds <= 0)
      return HD_ConfigError("AutoReHedge requires positive TimeoutSeconds.");

   if(InpEnableTrailingTP && !InpEnablePersistence)
      return HD_ConfigError("Trailing TP requires Persistence enabled.");

   if(InpMagicNumber == 0)
      return HD_ConfigError("MagicNumber must not be zero.");

   if(InpEnableSessionFilter)
   {
      if(InpEnableSession1 && !HD_ValidSession(InpSession1Time))
         return HD_ConfigError("Invalid Session1.");

      if(InpEnableSession2 && !HD_ValidSession(InpSession2Time))
         return HD_ConfigError("Invalid Session2.");

      if(InpEnableSession3 && !HD_ValidSession(InpSession3Time))
         return HD_ConfigError("Invalid Session3.");
   }

   return true;
}

#endif