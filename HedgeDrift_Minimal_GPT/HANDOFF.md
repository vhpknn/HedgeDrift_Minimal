# HANDOFF — HedgeDrift Minimal GPT

> Last updated: 2026-10-08, Asia/Bangkok (UTC+07:00)
> Purpose: เอกสารส่งต่องานให้ AI/ผู้พัฒนาคนถัดไป
> Current milestone: Phase 1–4 + Trailing TP + Profit Guard + Auto Re-Hedge ประกอบแล้วและ Compile ผ่าน
> Release status: COMPILE-PASSED / INTEGRATION-TEST-PENDING
> ห้ามตีความว่า Compile ผ่าน = Runtime, Recovery หรือ Risk ผ่านครบแล้ว

---

## 0. อ่านก่อนเริ่มงาน

### 0.1 Source of Truth

ลำดับการอ้างอิง:

1. คำสั่งและสเปกล่าสุดที่ผู้ใช้อนุมัติ
2. Git Repository ที่ Commit ระบุ
3. HANDOFF.md นี้
4. Blueprint รุ่นเก่า ใช้เฉพาะส่วนที่ไม่ขัดกับข้อกำหนดล่าสุด

Repository:

https://github.com/vhpknn/HedgeDrift_Minimal

Current baseline commit:

98e12e954d1c8ba744378edadbf9d3edb97eb25b

Short hash:

98e12e9

ก่อนทำ FIND/REPLACE ต้องตรวจซอร์สและ Diff ของฐานที่ใช้จริง
ห้ามใช้ ac464b0, 8ed35ad, 98b6bc4 หรือ eb2033c เป็นฐานล่าสุดของฟีเจอร์ใหม่โดยไม่ตั้งใจ

### 0.2 กติกาการทำงาน

- ส่ง Code ในแชตเท่านั้น ห้ามสร้างไฟล์ดาวน์โหลด
- ไฟล์ใหม่: ส่ง Full Code พร้อม Path
- ไฟล์เดิม: ส่ง FIND / REPLACE พร้อม Path
- ห้ามส่ง Full Code ของไฟล์เดิม เว้นแต่ผู้ใช้ขอ "ขอ fullcode"
- ทำ Mini-Batch รวมส่วนแก้ที่เกี่ยวข้องกัน
- Compile รวมหลังประกอบครบชุด ไม่สั่งเทสต์ยิบย่อยทุกบรรทัด
- Runtime ใช้ Master Integration Checklist รวมรอบเดียว
- หากเป็น Environment/Path Error ให้หยุดแก้ Logic ก่อน
- ใช้ Git/Commit/Diff เป็นหลัก ไม่ขอ Source ทั้งชุดซ้ำ
- ไม่เพิ่ม Helper แยกไฟล์โดยไม่จำเป็น
- เพดานโมดูล: 8 ไฟล์ .mqh
- ทุกฟังก์ชันที่เปิด/ปิดได้ต้องมี bool ชัดเจน
- ห้ามใช้ 0/-1/ข้อความว่างเป็นสวิตช์เปิด–ปิดฟังก์ชัน
- ค่า 0 ภายในสถานะ/ตัวจับเวลาไม่ถือเป็นการใช้ Input แทน bool
- Log ใช้ Prefix เช่น [HedgeDrift][INFO], [WARN], [ERROR]
- ห้ามรื้อ Core Execution, State Machine หรือ Recovery เพื่อเพิ่ม Trailing/Re-Hedge
- ห้ามเพิ่ม Martingale, Recovery Lot, Lot Multiplier หรือระบบคาดเดาทุนโดยไม่ได้สั่ง

### 0.3 Security

เคยมี GitHub Token ถูกส่งในแชต
ห้ามนำ Token นั้นมาใช้หรือคัดลอกลงเอกสาร/โค้ด
ผู้ใช้ควร revoke Token ที่เปิดเผยแล้ว
ใช้ GitHub Connector ที่เชื่อมไว้ ไม่ต้องขอ Token ใหม่

---

## 1. Project Location & Architecture

### 1.1 Local root

W:\MT4_MT5_Portable\Editor\Metaeditor_MT5_Portable\MQL5\Experts\HedgeDrift_Minimal\HedgeDrift_Minimal_GPT\

### 1.2 Folder rule

Include อยู่ภายในโฟลเดอร์เดียวกับ EA
ห้ามย้ายโมดูลของโปรเจกต์ไป MQL5\Include ส่วนกลาง

### 1.3 Current structure

HedgeDrift_Minimal_GPT/
├── HANDOFF.md
├── HedgeDrift_Minimal_GPT.mq5
└── Include/
    ├── Config.mqh
    ├── RuntimeState.mqh
    ├── AccountingEngine.mqh
    ├── TradeEngine.mqh
    ├── PanelEngine.mqh
    ├── RiskEngine.mqh
    ├── StrategyEngine.mqh
    └── Persistence.mqh

HANDOFF.md เป็นเอกสาร ไม่ใช่โมดูลที่ 9

### 1.4 Module responsibilities

| File | Responsibility |
|---|---|
| Config.mqh | Inputs, Enum, Validation, Order Comment |
| RuntimeState.mqh | Runtime switches, Cycle, Mode, Direction, Lock Price |
| AccountingEngine.mqh | Virtual Balance/Equity, Refill, Deal deduplication, History replay |
| TradeEngine.mqh | Native OrderSend, Hard SL, Modify SL, Close Ticket/Basket, side guards |
| PanelEngine.mqh | ปุ่ม Manual/สวิตช์, Contrast, Responsive Layout, Minimize |
| RiskEngine.mqh | Initial Risk, Basket RR, Fixed/Dynamic BE, Peak, Trailing TP, replacement registration |
| StrategyEngine.mqh | Manual/Timeout/Lock routing, Session, Re-Lock, Auto Cycle, Re-Hedge timers/intent |
| Persistence.mqh | Flat JSON snapshot, validation, checksum, backup, lock, Save/Load |
| HedgeDrift_Minimal_GPT.mq5 | เชื่อม Events, Recovery, Replay, Helpers และ Save lifecycle |

### 1.5 Native execution

โปรเจกต์ไม่ใช้ CTrade หรือ <Trade\Trade.mqh> แล้ว

เหตุผล:
เครื่องเป็น Portable และ Standard Library ที่ดาวน์โหลดทีละไฟล์ไม่เข้ากันกับ Compiler

ใช้:
- MqlTradeRequest
- MqlTradeResult
- OrderSend()
- TRADE_ACTION_DEAL
- TRADE_ACTION_SLTP

Filling:
- เลือก FOK ก่อน
- หาก Symbol รองรับ IOC แทน ใช้ IOC
- RETURN-only execution ยังไม่รองรับใน engine นี้
- ห้ามเติม Standard Library เก่ากลับมาเพื่อแก้ปัญหาโดยไม่จำเป็น

---

## 2. Current System Status

### 2.1 Validation levels

| Item | Status | Evidence |
|---|---|---|
| Phase 1 Compile | [*] | ผู้ใช้รายงาน 0 errors, 0 warnings |
| Phase 1 Runtime เดิม | [*] | Display, Init และ BaseCapital Validation ผ่านตามรายงานผู้ใช้ |
| Phase 2 Compile | [*] | Native OrderSend Compile ผ่าน |
| Phase 2 Runtime เดิม | [*] | BUY/SELL/HEDGE, Refill, Lock, Reject Guard, Close All ผ่านตามรายงานและ Log |
| Phase 3 Compile | [*] | ผู้ใช้รายงาน 0 errors, 0 warnings |
| Phase 3 Runtime เบื้องต้น | [*] | เปิดไม้, Hard SL ใน Terminal, State Machine ตามรายงานผู้ใช้ |
| Phase 3 Runtime ครบชุด | [ ] | ยังรอ Master Integration Test |
| Phase 4 Compile | [*] | 0 errors, 0 warnings, 1898 ms |
| Phase 4 Recovery ครบชุด | [ ] | ยังรอ Master Integration Test |
| Trailing TP / Re-Hedge Compile | [*] | 0 errors, 0 warnings, 2257 ms |
| Trailing TP / Re-Hedge Runtime ครบชุด | [ ] | ยังรอ Master Integration Test |
| Production/เงินจริง readiness | [ ] | ยังไม่ผ่านการตรวจรับรวม |

ผล Runtime ของรุ่นก่อนหน้าไม่ใช่หลักฐาน Regression PASS ของ Commit ล่าสุด
ตาราง Master Checklist ด้านล่างจึงเริ่มเป็น [ ] ทุกข้อ

### 2.2 Compile report ล่าสุด

User-reported result:

0 errors, 0 warnings, 2257 ms elapsed, cpu='X64 Regular'

รายงานในบทสนทนา:
2026-10-08 ประมาณ 08:01 น. เวลาไทย

AI ไม่ได้รัน MetaEditor หรือ Compile ด้วยตนเอง
Commit message และ Diff สอดคล้องกับชุดฟีเจอร์ที่ผู้ใช้รายงาน

### 2.3 Thai Tooltip UI Extension

Status:

- Code delivery: ส่ง FIND/REPLACE ในแชตแล้ว
- Base commit: 98e12e9
- Compile: [ ]
- Runtime hover/resize: [ ]
- New commit: ยังไม่ระบุ

Scope:

- เพิ่ม OBJPROP_TOOLTIP ภาษาไทยให้ทุก Object ของ Panel
- แยก METRICS เป็น Label EQ / OR / TT
- ใช้ค่า Accounting เดิม ไม่แก้สูตร
- Refill tooltip อ่าน InpRefillAmount จริง
- Minimize tooltip เป็นไทยและเปลี่ยนตามสถานะ
- คง Contrast/Scaling/Minimize เดิม
- ไม่แก้ Trade/Risk/Strategy/Accounting/Persistence
- ไม่เพิ่มไฟล์ .mqh
- ไม่แก้ KI-001 Timer reset gap ในชุด UI นี้

Correct terminology:

- EQ = VirtualBalance หลังรับรู้ผลปิดแล้ว
- OR = Floating Profit + Swap ของสถานะ EA นี้
- TT = EQ + OR ไม่ใช่ Target
- Ref = Refill total/count ไม่ใช่กำไรหรือจำนวนไม้
- Refill ไม่เปลี่ยน Base Capital และไม่ใช่ฝากเงินจริง
- Session Filter ใช้กับ Lock Mode ไม่บล็อก Manual/Re-Hedge
- Close All ไม่ลบทุน/ประวัติ และไม่ปิด AutoNewCycle

Native Tooltip:

- Terminal เป็นผู้จัดการเวลาหน่วง Hover
- ไม่รับรองว่า Popup จะเด้งทันทีแบบ Custom UI
- ต้องตรวจภาษาไทยไม่เป็นสี่เหลี่ยมหรือข้อความเสีย
- ต้องตรวจ Label ไม่ถูก Background แย่ง Hover

### 2.4 Version naming

- Panel/runtime label: v2.1
- #property version ใน EA เดิม: 2.10
- เอกสาร Blueprint มีชื่อรุ่นอื่นร่วมอยู่
- ห้ามเปลี่ยนเวอร์ชันทั้งหมดเองโดยไม่สั่ง

---

## 3. Commit History & Stable Build

คำว่า Stable ในเอกสารนี้หมายถึง Compile baseline
ไม่ใช่ยืนยัน Runtime/Production stable

เวลาตารางนี้เป็น Asia/Bangkok UTC+07:00

| Commit | Date/time | Milestone |
|---|---|---|
| ac464b0 | 2026-10-07 18:35:35 | ชุด Manual/Panel ที่ยังใช้ CTrade |
| 4d386cc | 2026-10-07 18:46:11 | Intermediate commit; ตรวจ Diff ก่อนใช้ |
| 8ed35ad | 2026-10-07 19:18:19 | เปลี่ยน Trade Engine เป็น Native OrderSend |
| 98b6bc4 | 2026-10-07 22:56:57 | Phase 3 Risk/Strategy + Responsive/Contrast/Minimize UI |
| eb2033c | 2026-10-08 07:30:17 | Phase 4 Persistence/Recovery + Timeout Hedge |
| 98e12e9 | 2026-10-08 08:02:42 | Trailing TP + Profit Guard + Auto Re-Hedge; latest compile baseline |

Full latest hash:

98e12e954d1c8ba744378edadbf9d3edb97eb25b

Commit message:

GPT-Trailing TP + Profit Guard + Auto Re-Hedge — compile passed

### Build record สำหรับอัปเดตครั้งต่อไป

- New commit:
- MetaEditor/MT5 build:
- Compile result:
- Compile duration:
- Runtime evidence:
- Integration checklist revision:
- Rollback baseline:

---

## 4. All Input Parameters

ตารางนี้เป็น Default จากซอร์ส ไม่ใช่ยืนยันค่าที่กำลังรันบนกราฟ
ต้องเก็บ .set ที่ใช้จริงประกอบทุกผลทดสอบ

### 4.1 Virtual Capital / Auto Lot

| Input | Type | Default | Meaning / Current implementation |
|---|---|---|---|
| InpEnableAutoLot | bool | true | มี Input/Runtime switch แต่สูตร Auto-Lot ยังไม่เชื่อมกับ Execution |
| InpBaseCapital | double | 50.0 | ทุนจำลองเริ่มต้น |
| InpStartLot | double | 0.01 | Lot ที่ใช้เปิดจริงในชุดปัจจุบัน |
| InpStepCapital | double | 50.0 | ค่าตั้งสำหรับ Auto-Lot ที่ยังไม่เชื่อม |
| InpStepLot | double | 0.01 | ค่าตั้งสำหรับ Auto-Lot ที่ยังไม่เชื่อม |
| InpRefillAmount | double | 10.0 | จำนวนทุนจำลองที่เพิ่มเมื่อกด Refill |

ข้อห้าม:
ห้ามรายงานว่า Auto-Lot ทำงานแล้วเพียงเพราะ InpEnableAutoLot=true
Execution ปัจจุบันยังส่ง InpStartLot และ Panel ระบุ FIXED LOT

### 4.2 Hard Risk Control

| Input | Type | Default | Meaning |
|---|---|---|---|
| InpEnableHardCutLoss | bool | true | ใส่ Hard SL ในคำสั่งเปิด |
| InpCutLossPoints | int | 1000 | ระยะอ้างอิง Hard SL/RR |

### 4.3 Strategy / Direction / Cycle

| Input | Type | Default | Meaning |
|---|---|---|---|
| InpStrategyMode | ENUM_STRATEGY_MODE | MODE_LOCK_PRICE | โหมดหลัก |
| InpTradeDirection | ENUM_TRADE_DIRECTION | DIR_BOTH | Direction ของ Lock strategy |
| InpEnableHedgeTriggerLock | bool | true | เปิดตัวจับ Lock trigger |
| InpLockDistancePoints | int | 1000 | ระยะจาก Lock |
| InpEnableCutLossReLock | bool | true | HardCut Re-Lock สำหรับ Lock Mode |
| InpEnableAutoNewCycle | bool | true | เริ่มรอบทั่วไปถัดไปเมื่อจบ Basket |
| InpEnableCycleTimeout | bool | true | เปิด Timer ของ Timeout Mode |
| InpTimeoutSeconds | int | 300 | ใช้ทั้ง Timeout Mode และระยะรอ Re-Hedge |

Enum Strategy:

- 0 = MODE_TIMEOUT_HEDGE
- 1 = MODE_LOCK_PRICE
- 2 = MODE_MANUAL_FREE

Enum Direction:

- 0 = DIR_BUY_ONLY
- 1 = DIR_SELL_ONLY
- 2 = DIR_BOTH
- 3 = DIR_HEDGE

คำเตือน:
.set เก่าที่ใช้ MODE_TIME_SESSION=0 จะถูกตีความเป็น Timeout ในซอร์สปัจจุบัน
ห้ามนำชื่อ Time Session เดิมกลับมาครอบ Timeout/Manual

### 4.4 Profit Protection & Targets

| Input | Type | Default | Meaning |
|---|---|---|---|
| InpEnableAutoBE | bool | true | Fixed/Dynamic BE |
| InpBETriggerPoints | int | 1000 | กำไรเป็น Points ก่อนเริ่ม BE |
| InpBELockPercent | double | 20.0 | สัดส่วนระยะที่ล็อก |
| InpBEType | ENUM_BE_TYPE | BE_TYPE_FIXED | 0 Fixed / 1 Dynamic |
| InpEnableRRTarget | bool | true | Basket target จาก Initial Risk |
| InpRRTargetPercent | double | 100.0 | 100% = 1 เท่าของ Initial Risk |
| InpEnableTrailingTP | bool | false | Peak-based close แยก Position |
| InpTrailingStepPoints | int | 500 | ระยะย้อนจาก Peak |
| InpEnableAutoReHedge | bool | true | ดูแลคู่ Hedge และเติมขาที่หาย |

### 4.5 Sessions

| Input | Type | Default | Meaning |
|---|---|---|---|
| InpEnableSessionFilter | bool | true | Master filter ของ Lock Mode เท่านั้น |
| InpEnableSession1 | bool | true | เปิด Session 1 |
| InpSession1Time | string | 01:30-05:00 | เวลา Server |
| InpEnableSession2 | bool | true | เปิด Session 2 |
| InpSession2Time | string | 10:00-14:00 | เวลา Server |
| InpEnableSession3 | bool | true | เปิด Session 3 |
| InpSession3Time | string | 21:00-24:00 | เวลา Server |

ช่วงเวลาใช้แบบ [start, end)
รองรับช่วงข้ามเที่ยงคืน
Filter ไม่บล็อก Manual หรือ Auto Re-Hedge

### 4.6 Persistence / Identity

| Input | Type | Default | Meaning |
|---|---|---|---|
| InpEnablePersistence | bool | true | Snapshot/Recovery |
| InpPersistenceInTester | bool | false | ไม่ใช้ state ข้ามรัน Tester โดยค่าเริ่มต้น |
| InpMagicNumber | ulong | 998874 | เจ้าของสถานะและ state identity |

ไม่มี InpEAComment ใน Config ปัจจุบัน
Order Comment สร้างจาก HD_OrderComment() ตามค่า RR

### 4.7 Panel controls

Manual actions:

- BUY
- SELL
- HEDGE OPEN
- LOCK PRICE
- REFILL
- CLOSE ALL
- Minimize / Panel

Runtime controls:

- Mode
- Direction
- BE Type
- Hard SL
- Auto BE
- RR
- Session Filter
- Re-Lock

ข้อจำกัด:

- Mode/Direction/Hard SL/RR เปลี่ยนเมื่อ Basket ว่าง
- Auto BE/BE Type/Session/Re-Lock เปลี่ยนได้ตาม Guard ในโค้ด
- ปิด Auto BE ไม่ลบ SL ที่เคยเลื่อนแล้ว
- เปลี่ยน Dynamic เป็น Fixed ไม่ดึง SL ถอย
- Trailing TP และ Auto Re-Hedge ควบคุมจาก Inputs ยังไม่มีปุ่มเฉพาะบน Panel

---

## 5. Execution & Risk Contracts

### 5.1 State Machine

IDLE → WAIT_TRIGGER → OPENING → ACTIVE → CLOSING → IDLE

มี 5 สถานะไม่ซ้ำ
IDLE ที่ปลายเป็นการกลับมาสถานะเดิม

ชื่อ HD_RunPhase3() ยังคงอยู่ในไฟล์หลัก
แม้ข้างในเชื่อม Phase 4 และฟีเจอร์ใหม่แล้ว
อย่าใช้ชื่อฟังก์ชันเป็นหลักฐานว่าระบบยังอยู่ Phase 3 เท่านั้น

### 5.2 Three isolated strategies

| Strategy | Trigger | Action |
|---|---|---|
| Manual | กด Panel | เปิดตามปุ่มทันที |
| Timeout | Pos=0 ต่อเนื่องครบเวลา | เปิด Hedge BUY+SELL |
| Lock | Crossing ระดับ Lock | เปิดตาม Trigger/Direction และ Session |

Manual bypass:

- ข้าม Session, Lock Crossing และ Timeout
- ไม่ข้าม Single Basket Guard
- ไม่ข้าม Trading Permission, Lot, Order/Position ownership หรือ Risk

Timeout:

- ใช้เวลา Server
- Trigger เปิดจาก market tick ไม่ใช่ OnTimer ส่งคำสั่งเอง
- หลังครบเวลา ต้องมี tick ใหม่จึงทำงาน
- ไม่ทำงานทับ Basket ที่มีอยู่
- การวนรอบทั่วไปขึ้นกับ AutoNewCycle
- แยกจาก missing-side timers ของ Re-Hedge

Lock:

- Trigger ปัจจุบันใช้ midpoint ของ Bid/Ask
- Lower crossing → BUY
- Upper crossing → SELL
- Both เลือกตาม Trigger ไม่ใช่เปิดสองฝั่งทันที
- Hedge เปิดคู่เมื่อ Trigger
- นอก Session อัปเดตราคาอ้างอิงแต่ไม่ replay crossing เก่าตอนเข้า Session

### 5.3 Single Basket / ownership

- Basket ใหม่เปิดได้เมื่อไม่มี Position และไม่มี Order ของ EA ค้าง
- จำกัด Symbol + Magic
- Close All ไม่ปิดไม้ต่างเจ้าของ
- Re-Hedge เป็นข้อยกเว้นผ่าน Helper เติมเฉพาะ missing side
- ห้ามปลด Guard ของ Open() เดิมเพื่อให้ Re-Hedge ผ่าน

### 5.4 Virtual accounting

VirtualBalance / EQ:

BaseCapital + RefillTotal + RealizedNetPnL

FloatingNetPnL / OR:

ผลรวม POSITION_PROFIT + POSITION_SWAP ของสถานะที่เปิดและเป็นของ EA

VirtualEquity / TT:

EQ + OR

Realized ของ Deal ที่ติดตาม:

DEAL_PROFIT + DEAL_COMMISSION + DEAL_SWAP + DEAL_FEE

ข้อจำกัด:
ค่าใช้จ่ายที่โบรกเกอร์ลงเป็นรายการแยกต่างหากนอก Buy/Sell Deal
ยังไม่ควรอ้างว่าครอบคลุมทั้งหมดโดยไม่ตรวจรูปแบบบัญชีจริง

### 5.5 Hard SL

- ใส่ SL ในคำสั่งเปิด
- ตรวจ Stops Level และ Tick Size
- ระยะ invalid → ปฏิเสธการเปิด
- ไม่ขยาย SL หรือถอด SL เพื่อบังคับให้คำสั่งผ่าน
- Slippage อาจทำให้ระยะจากราคาเปิดจริงต่างจากราคาก่อนส่ง

### 5.6 Fixed/Dynamic BE

Fixed:

LockPoints = BETriggerPoints × BELockPercent / 100

Dynamic หลังถึง Trigger:

Basis =
BETriggerPoints
+ 10 × floor((ProfitPoints - BETriggerPoints) / 10)

LockPoints = Basis × BELockPercent / 100

- BUY ใช้ Bid วัดกำไร
- SELL ใช้ Ask วัดกำไร
- SL ไม่ถอยหลัง
- จัดราคาให้ตรง Tick Size
- ต้องผ่าน Stops/Freeze restrictions
- ปิด Auto BE ไม่ลบ SL เดิม

### 5.7 Basket RR

- InitialRiskMoney คำนวณด้วย OrderCalcProfit จากราคาเปิดจริงถึง SL/reference distance
- ล็อกเมื่อเปิด Basket ครบ
- TargetMoney = InitialRiskMoney × RRPercent / 100
- ปิด Basket เมื่อ OR >= TargetMoney
- Partial Close ไม่ลด Target
- BE ไม่ลด Initial Risk
- Re-Hedge ไม่เรียก BeginBasket ใหม่
- RR ปิดทั้ง Basketและยกเลิก Re-Hedge ของรอบนั้น

ข้อจำกัด:

- RR เป็น reference target ไม่ใช่ cumulative loss cap
- OR trigger ไม่ได้รับประกันกำไรสุทธิหลัง closing costs/slippage
- ถ้า Hard SL OFF ใช้ CutLossPoints เป็นระยะอ้างอิง RR
- Server TP อาจเป็น 0 เพราะ RR/Trailing ใช้ EA สั่งปิด

---

## 6. Trailing TP & Auto Re-Hedge

### 6.1 Trailing TP — Option A

แยกตาม Position Identifier:

BUY:
Best Price = Bid สูงสุดที่ EA เห็น
Trigger เมื่อ BestBid - CurrentBid >= StepPoints × Point

SELL:
Best Price = Ask ต่ำสุดที่ EA เห็น
Trigger เมื่อ CurrentAsk - BestAsk >= StepPoints × Point

Profit Guard:

POSITION_PROFIT > 0

- ตรวจตอนเตรียม และก่อนส่งคำสั่งปิด
- ปิด Ticket นั้นเท่านั้น ไม่ Close All
- Profit Guard ไม่ใช่ Profit+Swap+Commission
- ถ้ายังไม่มีกำไร ไม่ reset Peak เพื่อหลบเงื่อนไข
- เมื่อ trigger แล้วจะเก็บ trail_pending สำหรับ intent/retry
- Retry Trailing ไม่เกินหนึ่งครั้งต่อ server second
- Peak และ intent ต้อง Save ก่อนส่งคำสั่งปิด
- ไม้ใหม่เริ่ม Peak ใหม่ ไม่รับ Peak ของไม้เดิม

ข้อจำกัด:

- ไม่รู้ peak ที่เกิดระหว่าง EA/เน็ตไม่ทำงาน
- กู้ได้เฉพาะ peak ที่บันทึกสมบูรณ์แล้ว
- Profit > 0 ก่อนส่งไม่รับประกัน realized profit > 0 หลัง fill
- Trailing เป็น logic ฝั่ง EA ไม่ใช่ Server TP

### 6.2 Auto Re-Hedge

Arm เมื่อ:

- เปิด Hedge สำเร็จ
- BUY=1 และ SELL=1
- InpEnableAutoReHedge=true

ไม่ Arm จากการเปิด BUY-only/SELL-only โดยลำพัง

เมื่อขาหาย:

- เริ่ม timer ของฝั่งนั้นจาก DEAL_TIME
- BUY และ SELL มี timer แยกกัน
- Partial Close ที่ยังเหลือ Position ไม่ถือว่าขาหาย
- ครบ InpTimeoutSeconds → เติมเฉพาะฝั่งที่ Count=0
- ไม่รอ Session/Lock
- ไม่เปิด B2/S2
- ตรวจ pending orders และ permission ก่อนส่ง
- ไม้เติมใช้ InpStartLot ตามชุด FIXED LOT
- ลงทะเบียน replacement แทน slot ของไม้ที่ปิด
- คง Peak ของฝั่งที่ยังอยู่และ Initial Risk ของรอบ

แหล่งปิดที่เริ่ม timer:

- Trailing TP
- Hard SL
- BE
- Manual close รายไม้ผ่าน Terminal ในรอบ Hedge ที่ Arm อยู่

### 6.3 Reset/End-round exceptions

หยุด Re-Hedge เมื่อ:

- CLOSE ALL บน Panel
- Basket RR/เจตนาปิดทั้ง Basket
- ผู้ใช้เปลี่ยน Mode เมื่อว่าง
- เปิด Basket ใหม่อย่างชัดเจน
- InpEnableAutoReHedge=false ทำให้ไม่ active

ข้อสำคัญ:

- Close All ยกเลิก Re-Hedge แม้ทั้งสองฝั่งว่างและกำลังรอเติม
- AutoNewCycle ของ strategy เดิมไม่ได้ถูกปิดโดย Close All
- ถ้าจะพิสูจน์ว่าไม่มีรอบใหม่ ให้ใช้ Manual + AutoNewCycle OFF
- การรักษา B1 S1 เป็นเป้าหมายหลังเติมสำเร็จ ไม่ได้มีสองขาตลอด 300 วินาทีที่รอ

---

## 7. State & Persistence Specification

### 7.1 Storage

Relative sandbox path:

HedgeDrift\<login>_<server-hash>_<symbol-hash>_<magic>\state.json

Actual identity ภายในไฟล์ตรวจ:

Account Server + Login + Symbol + Magic

ไฟล์ร่วม:

- state.json
- state.json.bak
- state.json.tmp
- state.lock

- ไม่ใช้ FILE_COMMON โดยค่าเริ่มต้น
- File lock ไม่มี share flags เพื่อกันเจ้าของซ้ำใน sandbox เดียวกัน
- Terminal คนละ data folder มี sandbox คนละที่ ไม่ใช่ global lock ข้ามทุก terminal
- Tester มี agent sandbox แยก
- Runtime files ไม่ใช่ไฟล์ source ในโฟลเดอร์ Experts

### 7.2 Format

Flat JSON ของ EA เอง
ค่าทุกตัวเก็บเป็น JSON string

ตัวอย่างความหมาย:

- bool → "0" / "1"
- ulong ticket → decimal string ไม่ผ่าน double
- double → decimal string
- รายการ ID → CSV อยู่ภายใน string ไม่ใช่ JSON array

Schema ปัจจุบัน:

- schema = "1"
- feature_version = "1"
- trail_version = "1"
- rh_version = "1"

Checksum เป็น integrity check สำหรับความเสียหายโดยอุบัติเหตุ
ไม่ใช่ security signature และไม่ใช่ proof of atomic write

### 7.3 Metadata keys

| Key | Meaning |
|---|---|
| schema | schema ของรูปแบบไฟล์ |
| identity | ตัวตนบัญชี/Server/Symbol/Magic ที่ encode แล้ว |
| settings | fingerprint ของ Input settings |
| feature_version | marker รุ่น Trailing/Re-Hedge |
| checksum | checksum ของ body |
| complete | marker ว่าไฟล์เขียนครบ |

### 7.4 Runtime keys

| Key | Meaning |
|---|---|
| rt_cycle | State Machine |
| rt_strategy | Strategy Mode |
| rt_direction | Direction |
| rt_be_type | Fixed/Dynamic |
| rt_lock | Lock Price |
| rt_since | เวลาเริ่มสถานะ |
| rt_flags | CSV ของ bool runtime switches |

ลำดับ rt_flags:

0. auto_lot
1. hard_cut_loss
2. hedge_trigger_lock
3. cut_loss_relock
4. auto_new_cycle
5. cycle_timeout
6. auto_be
7. rr_target
8. session_filter
9. session1
10. session2
11. session3

Trailing/Re-Hedge ไม่มี Runtime Panel bool ใน array นี้
ใช้ Inputs และ settings fingerprint

### 7.5 Accounting keys

| Key | Meaning |
|---|---|
| acc_base | Base Capital ของบัญชีจำลอง |
| acc_refill | Refill total |
| acc_refill_count | จำนวนครั้งเติม |
| acc_realized | Realized net |
| acc_epoch | จุดเริ่มช่วงบัญชี |
| acc_deals | Deal IDs ที่ลงบัญชีแล้ว |
| acc_positions | Position IDs ที่เป็นของ EA |

OR ไม่ถูกโหลดจากไฟล์
คำนวณใหม่จาก live positions

### 7.6 Risk / Peak / Close Intent keys

Global:

- risk_initial
- risk_ready
- risk_closing
- risk_count
- trail_version

Per item, index i:

- risk_i_id
- risk_i_sl
- risk_i_hard
- risk_i_side
- risk_i_side_known
- risk_i_peak
- risk_i_peak_ready
- risk_i_trail_pending

side:

- 0 = BUY
- 1 = SELL

รายการ Risk จำกัดสอง slot สำหรับคู่ B1 S1
replacement ใช้ slot ที่ไม่มี Position เดิมอยู่แล้ว

### 7.7 Strategy / Timeout keys

- strategy_spent
- strategy_seen
- strategy_relock
- strategy_wait

ราคา previous crossing ไม่ถูกกู้เพื่อ replay signal เก่าช่วง downtime
เริ่มอ้างอิง Quote ใหม่หลังโหลด

### 7.8 Re-Hedge Timer / Intent keys

| Key | Meaning |
|---|---|
| rh_version | รุ่นข้อมูล Re-Hedge |
| rh_armed | กำลังดูแลคู่ Hedge |
| rh_buy_wait | BUY timer active |
| rh_sell_wait | SELL timer active |
| rh_buy_since | BUY missing timestamp |
| rh_sell_since | SELL missing timestamp |
| rh_intent | มีเจตนาเติมที่ต้องตรวจ |
| rh_side | ฝั่งที่จะเติม 0 BUY / 1 SELL |
| rh_intent_since | เวลาก่อนส่งคำสั่งเติม |

Timer ใช้ server datetime
รวมเวลาที่ผ่านระหว่างปิด EA ตาม snapshot/history ที่ตรวจได้
หลังครบต้องมี tick ใหม่และผ่าน Guard จึงส่งคำสั่ง

### 7.9 Save lifecycle

HD_SaveState():

1. Begin snapshot
2. Save runtime
3. Save accounting
4. Save risk/peaks
5. Save strategy/timers/intent
6. Commit file
7. MarkSaved สำหรับ peak dirty เมื่อสำเร็จ

Write flow:

Temp → FileFlush → Close → Backup → FileMove replace main

ไม่รับประกัน atomic filesystem transaction/ทุกกรณีไฟดับ

Save points:

- Initial successful load
- ก่อนเปิด Basket
- หลังเปิด/register risk
- หลัง Deal replay
- Refill/Lock/Panel switches
- ก่อนส่ง Trailing close
- เมื่อ Peak เปลี่ยน
- ก่อนส่ง Re-Hedge
- หลังลงทะเบียน replacement
- Timer refresh เมื่อ state เปลี่ยน
- OnDeinit ที่ initialized/recovery valid

ถ้า body ไม่เปลี่ยน ไม่เขียนซ้ำ
แต่ peak ที่เปลี่ยนสามารถทำให้เกิด disk writes บ่อยได้

### 7.10 Recovery sequence

1. Validate Config
2. Init Trade
3. Acquire state lock
4. Init Accounting context
5. Reject outstanding orders ที่ยังยืนยันไม่ได้
6. Load main หรือ valid backup
7. ตรวจ identity/checksum/settings
8. Restore runtime/accounting/risk/strategy
9. Collect History tickets ก่อน replay
10. Process เฉพาะ deals ที่ยังไม่เคยนับ
11. Observe missing-side timers/Re-Lock จาก accepted deals
12. Resolve saved Re-Hedge intent กับ live position
13. ตรวจ CoversLiveBasket()
14. หาก flat และ settings เปลี่ยน ใช้ Inputs ใหม่แต่คงบัญชี
15. Save snapshot ที่กระทบยอดแล้ว
16. จึงอนุญาตเปิดใหม่

### 7.11 Failure contracts

- ไม่มี state + ไม่มีไม้: fresh account
- ไม่มี state + มีไม้: INIT_FAILED ไม่เดา Initial Risk
- invalid snapshot ทั้ง main/backup: INIT_FAILED ไม่เขียน fresh ทับหลักฐาน
- settings เปลี่ยนขณะมี Basket: ปฏิเสธ
- ID/risk/intent ไม่ตรง: บล็อกหรือปฏิเสธ Init ตามตำแหน่งที่พบ
- History failure: บล็อก new entries
- Save failure: บล็อก new entries; existing risk ทำงานต่อได้ตามเส้นทางที่ยังรัน
- หาก INIT_FAILED: EA ไม่ได้รัน Risk; เหลือ Server SL ที่มีอยู่เท่านั้น
- Intent mismatch ใน runtime มี early return บางเส้นทาง: ห้ามอ้างว่า Risk ยังทำงานทุก tick โดยไม่ตรวจ

### 7.12 Legacy migration

Snapshot ก่อนฟีเจอร์ใหม่:

- ยอมรับ legacy Settings เมื่อไม่มี feature_version
- Missing Peak fields เริ่มจาก Quote หลังโหลด ไม่แต่ง Peak ย้อนหลัง
- Missing Re-Hedge fields เริ่ม unarmed
- ถ้ามีคู่ B1 S1 ครบ สามารถ adopt ได้ตาม Guard
- เหลือขาเดียวใน legacy snapshot ไม่เดา timer ย้อนหลัง

### 7.13 Limits

- Parser รับรูปแบบที่ EA สร้างเอง ไม่ใช่ general-purpose JSON parser
- Read size limit: 64 MiB
- CSV ID count limit: 200,000 ต่อรายการ
- Risk item count limit: 2
- ไม่ rebuild Initial Risk จาก SL หลัง BE เลื่อน
- Crash หลังเปิดจริงแต่ก่อน snapshot ครบ อาจต้อง manual inspection
- ไม่รับประกัน recovery ของ peak/tick ที่ไม่เคยบันทึก

---

## 8. Master Integration Test — Status Convention

ใช้เฉพาะ:

- [*] = ผ่านพร้อมหลักฐาน
- [-] = ไม่ผ่าน
- [ ] = ยังไม่ได้ทดสอบ / หลักฐานไม่พอ

ห้ามใส่ [*] เพียงเพราะไม่มี Error Log
ทุกแถวด้านล่างเริ่ม [ ] สำหรับ latest build

Record ต่อรอบ:

- Commit:
- MT5/MetaEditor build:
- Account type:
- Symbol:
- Magic:
- .set:
- Server time range:
- Test operator:
- Log location:
- State snapshot before/after:

### 8.1 Test preparation

- Demo แบบ Hedging
- สำรอง code/.set/state/backup
- เริ่มแต่ละกลุ่มด้วย Basket ว่างหรือ Magic แยก
- เปลี่ยน Inputs เมื่อว่าง
- ใช้เวลา Server วัด 300 วินาที
- ปิด RR เมื่อตรวจ BE/Trailing แยก
- ปิด Trailing/Re-Hedge เมื่อตรวจ Risk baseline แยก
- Tester ใช้จำลองราคา; restart/file recovery ตรวจ Demo ด้วย
- ไม่ทำ fault injection กับเงินจริง

---

## 9. Phase 1 Checklist

| ID | Status | Action Step | Expected Result |
|---|---|---|---|
| P1-01 | [ ] | Magic ใหม่ ไม่มี state/ไม้ | IDLE, Pos=0, EQ=Base, OR=0, TT=EQ; Fresh virtual account |
| P1-02 | [ ] | BaseCapital=0 แล้วโหลด | Config Error, Init rejected, ไม่มีเปิด |
| P1-03 | [ ] | Trailing ON, Step≤0 | Validation reject |
| P1-04 | [ ] | Re-Hedge ON, Timeout≤0 | Validation reject |
| P1-05 | [ ] | Refill 2 ครั้งก่อนเทรด | Ref=20(2), EQ=70 เมื่อ Base50/Amount10 |
| P1-06 | [ ] | เปิดไม้ เทียบ EQ/OR/TT | TT=EQ+OR; ไม่รวมต่าง Symbol/Magic |
| P1-07 | [ ] | ปิดผ่าน Terminal | EQ รับ net deal, OR ของไม้ปิดหาย |
| P1-08 | [ ] | โหลดซ้ำหลังปิด | Deal เดิมไม่ลงบัญชีซ้ำ |

---

## 10. Phase 2 Checklist

| ID | Status | Action Step | Expected Result |
|---|---|---|---|
| P2-01 | [ ] | ว่าง กด BUY | Buy1; OPENING→ACTIVE; execution log |
| P2-02 | [ ] | ปิดครบ กด SELL | Sell1 ไม่มี Buy แทรก |
| P2-03 | [ ] | ว่าง กด HEDGE OPEN | B1 S1; ไม่รายงานครบหากขาหนึ่งล้มเหลว |
| P2-04 | [ ] | กดเปิดซ้ำขณะมี Basket | Reject; ไม่มี B2/S2 |
| P2-05 | [ ] | Lock นอก Session กด Manual Hedge | เปิดทันทีโดย bypass entry filters |
| P2-06 | [ ] | Algo Trading OFF แล้วกดเปิด | ไม่มีไม้; permission error ไม่สำเร็จปลอม |
| P2-07 | [ ] | Lot ต่ำกว่า broker minimum | Reject ไม่เพิ่ม Lot เอง |
| P2-08 | [ ] | มี EA และต่าง Magic กด Close All | ปิดเฉพาะเจ้าของ EA |
| P2-09 | [ ] | ปิด Hedge ขาหนึ่งผ่าน Terminal | Pos1; บัญชีรับ Deal; ไม่จบ Basket ปลอม |
| P2-10 | [ ] | Minimize/Restore/Resize | ซ่อนปุ่มจริง; ON textดำ; ไม่เปลี่ยนสถานะเทรด |

---

### 10.1 Thai Tooltip Checklist

| ID | Status | Action Step | Expected Result |
|---|---|---|---|
| UI-TT-01 | [ ] | Hover Header/Status/Cap | คำอธิบายไทยตรงหน้าที่ ไม่แสดงชื่อ Object เปล่า |
| UI-TT-02 | [ ] | Hover EQ / OR / TT แยกกัน | แต่ละ Label มี Tooltip ของตัวเอง นิยามตรง Accounting |
| UI-TT-03 | [ ] | Hover BUY/SELL/HEDGE | บอก Manual execution และ Basket guard ไม่อ้าง atomic hedge |
| UI-TT-04 | [ ] | Hover LOCK/REFILL/CLOSE | ข้อความตรงฟังก์ชัน Refill ใช้จำนวนจริง Closeไม่ลบบัญชี |
| UI-TT-05 | [ ] | Hover Mode/Dir/BE/Hard/RR/Session/Re-Lock | ข้อความตรงโหมด/ข้อจำกัดและไม่อ้าง Filterครอบทุกกลยุทธ์ |
| UI-TT-06 | [ ] | Hover Background/System Tags | คำอธิบายไทย และไม่แย่ง Tooltip ของปุ่ม/Label |
| UI-TT-07 | [ ] | พับ/ขยายแล้ว Hover ปุ่ม MINI | Tooltipไทยเปลี่ยนตามสถานะ EAยังทำงาน |
| UI-TT-08 | [ ] | Resize Chart เล็ก/ใหญ่ | EQ/OR/TT ไม่ซ้อน ปุ่มเดิมไม่เสีย Tooltipยังถูก |
| UI-TT-09 | [ ] | ถอด/แนบ EA ใหม่ | สร้าง Tooltipกลับครบ ไม่มี METRICS Objectเก่าค้าง |
| UI-TT-10 | [ ] | ปรับ RefillAmountเมื่อว่างแล้ว Hover | จำนวนใน Tooltipตรง Input ไม่ฝัง10/USD |
| UI-TT-11 | [ ] | ตรวจภาษาไทยบน Terminalจริง | อ่านได้ ไม่เป็นสี่เหลี่ยมหรือ encodingเสีย |
| UI-TT-12 | [ ] | เทียบค่าก่อน/หลัง UI Patch | EQ/OR/TT และ Risk/Trade logic ไม่เปลี่ยนจากการเพิ่มTooltip |

## 11. Phase 3 Checklist

### 11.1 Risk

| ID | Status | Action Step | Expected Result |
|---|---|---|---|
| P3-01 | [ ] | Hard SL ON เปิด Buy/Sell แยกรอบ | SL อยู่ถูกฝั่งใน Terminal |
| P3-02 | [ ] | SL distance invalid | Reject ไม่เปิดแบบถอด/ขยาย SL |
| P3-03 | [ ] | ตรวจ TP ใน Terminal | TP0 ไม่ใช่ FAIL ของ RR/Trailing ฝั่ง EA |
| P3-04 | [ ] | RR OFF ทดสอบ Fixed BE | ล็อกตาม Trigger×Percent ไม่เลื่อนต่อ |
| P3-05 | [ ] | RR OFF ทดสอบ Dynamic BE | เลื่อนตามขั้น10pts เมื่อ broker อนุญาต |
| P3-06 | [ ] | ราคาย่อหลัง BE | SL ไม่ถอย |
| P3-07 | [ ] | Dynamic→Fixed หลังเลื่อน | ไม่ดึง SL ไปแย่กว่าเดิม |
| P3-08 | [ ] | OR ถึง RR target | ปิดครบ; ถ้าเหลือยังรักษา close intent |
| P3-09 | [ ] | ปิดขาหนึ่ง | InitialRisk/Target ไม่ลด |
| P3-10 | [ ] | Lock+Re-Lock แล้ว Hard SL | Lock=actual close price |
| P3-11 | [ ] | BE/Manual Close | ไม่ HardCut Re-Lock |

### 11.2 Strategy isolation

| ID | Status | Action Step | Expected Result |
|---|---|---|---|
| P3-12 | [ ] | Manual ว่างเกิน300s ไม่เคย arm pair | ไม่เปิดอัตโนมัติ |
| P3-13 | [ ] | Timeout ว่าง300s | ไม่ก่อนเวลา; tickหลังครบเปิด Hedge |
| P3-14 | [ ] | Timeout มี Basket | ไม่เปิดทับ |
| P3-15 | [ ] | Lock crossing | เปิดตาม Trigger/Direction ไม่มี Timeout แทรก |
| P3-16 | [ ] | ราคาค้างเลยระดับหลังเปิด | ไม่ยิงซ้ำ |
| P3-17 | [ ] | Lock Session ON นอกเวลา | ไม่ auto open; Risk ดูแลเดิม |
| P3-18 | [ ] | Crossing นอกเวลา แล้วเข้า Session | ไม่ replay crossing เก่า |
| P3-19 | [ ] | Session OFF แล้ว crossing ใหม่ | ข้ามเวลาแต่ยังต้อง crossing |
| P3-20 | [ ] | AutoNewCycle OFF ปิดครบ | ไม่วนรอบทั่วไป; แยก Re-Lock/Re-Hedge |

---

## 12. Phase 4 Checklist

### 12.1 Snapshot/accounting

| ID | Status | Action Step | Expected Result |
|---|---|---|---|
| P4-01 | [ ] | Refill ถอด/แนบ Inputs เดิม | ยอด/จำนวนครั้ง/EQ/switches กลับเดิม |
| P4-02 | [ ] | มี Basket ปิด/เปิด MT5 ปกติ | ไม่เปิดเพิ่ม; live Pos/OR ถูก; Riskเดิม |
| P4-03 | [ ] | BE เลื่อนแล้ว restart | SL ไม่ลด; InitialRisk ไม่คำนวณใหม่ |
| P4-04 | [ ] | ถอด EA ปิดไม้ Terminal แล้วแนบ | Replay offline deal ครั้งเดียว |
| P4-05 | [ ] | โหลดซ้ำ2–3ครั้งหลัง replay | EQ ไม่เปลี่ยนซ้ำ |
| P4-06 | [ ] | เปลี่ยน .set เมื่อว่าง | บัญชีเดิม, Inputsใหม่ |
| P4-07 | [ ] | เปลี่ยนค่าที่ตรวจขณะมีไม้ | Reject ไม่ fresh overwrite |
| P4-08 | [ ] | EAอีกตัว identityเดียว sandboxเดียว | File lock กันการเขียนแข่ง |

### 12.2 Disconnect/corruption/intent

| ID | Status | Action Step | Expected Result |
|---|---|---|---|
| P4-09 | [ ] | เน็ตหลุดแล้วกลับ | ไม่เปิดซ้ำ; reconcile ข้อมูลจริง |
| P4-10 | [ ] | ปิด MT5 ฉับพลันบน Demo | ใช้ valid snapshot+history ไม่ resetทุน |
| P4-11 | [ ] | Mainเสีย Backupดี | Backup load+replay ไม่ fresh start |
| P4-12 | [ ] | ย้าย Main/Backupออกตอนมีไม้ | Recovery reject ไม่เดาทุน/เปิดเพิ่ม |
| P4-13 | [ ] | Snapshot ID ไม่ตรง | Guard reject ไม่จัดการไม้ผิด |
| P4-14 | [ ] | หยุดหลังส่งก่อน saveผล | ตรวจจริงก่อน retry ไม่เกิดไม้เบิ้ล |
| P4-15 | [ ] | Close All/RR ไม่ครบแล้ว restart | คืนเจตนาปิด ไม่เริ่มรอบใหม่ |

ถ้าจับ fault window ไม่ได้ ให้คง [ ]
INIT_FAILED หมายถึง EA ไม่รัน Risk ต้องตรวจ Terminal ทันที

---

## 13. Trailing TP Checklist

| ID | Status | Action Step | Expected Result |
|---|---|---|---|
| TR-01 | [ ] | BUY วิ่งขึ้น Trailing ON | Best Bid เพิ่มและไม่ลด |
| TR-02 | [ ] | SELL วิ่งลง | Best Ask ลดและไม่เพิ่ม |
| TR-03 | [ ] | BUY ย้อน500pts Profit>0 | ปิดเฉพาะ Buy |
| TR-04 | [ ] | SELL ย้อนครบ Profit>0 | ปิดเฉพาะ Sell |
| TR-05 | [ ] | ย้อนครบ Profit≤0 | ไม่ trailing close |
| TR-06 | [ ] | Save peak แล้ว restart | คืน Peak เดิม |
| TR-07 | [ ] | หลุดเน็ตหลัง Save peak | ใช้ saved Peak ไม่แต่งช่วงขาดข้อมูล |
| TR-08 | [ ] | เปิด replacement | ID/Peakใหม่ ไม่รับ Peakไม้เก่า |
| TR-09 | [ ] | Trailing OFF | ไม่ Helper close; Riskอื่นตาม switches |

Profit Guard ตรวจ pre-request
Realized profit หลัง fill ไม่ใช่หลักฐานเดี่ยวว่าตอนส่ง Guard ทำงานหรือไม่

---

## 14. Auto Re-Hedge Checklist

| ID | Status | Action Step | Expected Result |
|---|---|---|---|
| RH-01 | [ ] | Re-Hedge ON เปิด Hedge | B1S1; armed log |
| RH-02 | [ ] | เปิด Buy-only ไม่เคย arm | ไม่สร้าง Sell เอง |
| RH-03 | [ ] | ปิด Buy จับเวลาจาก Deal | B0S1, BUY timer, ไม่ก่อน300s |
| RH-04 | [ ] | RH-03 ครบ300s | เติม Buy1, Sellเดิม ไม่ S2 |
| RH-05 | [ ] | ปิด Sell แล้วครบเวลา | เติม Sellเท่านั้น |
| RH-06 | [ ] | ปิดด้วย Trailing/SL/BE แยก | timerฝั่งหาย ไม่รอ crossing |
| RH-07 | [ ] | Tickถี่/กดซ้ำหลังเติม | ไม่มี B2S1/B1S2 |
| RH-08 | [ ] | Partial close ยังมีPosition | ไม่ถือว่าขาหาย |
| RH-09 | [ ] | ปิดสองฝั่งคนละเวลา | timerแยก ไม่ resetอีกฝั่ง |
| RH-10 | [ ] | ทั้งสองว่างระหว่างรอเติม | Strategyใหม่ไม่เปิดแทรกรอบเดิม |
| RH-11 | [ ] | Restartระหว่างรอ | คืนเวลา ไม่เริ่มศูนย์ เติมเฉพาะที่ขาด |
| RH-12 | [ ] | ตรวจRiskหลังเติม | HardSLใหม่; InitialRisk/Targetเดิม |
| RH-13 | [ ] | permissionOFFตอนครบแล้วON | ไม่สำเร็จปลอม ไม่ spamทุกtick |
| RH-14 | [ ] | Re-Hedge OFF ก่อนรอบ | ไม่เติม |
| RH-15 | [ ] | LockนอกSession ขาหาย | เติมคู่เดิมได้ ไม่เปิดBasketอื่น |
| RH-16 | [ ] | Legacy snapshot | adoptคู่เต็มได้; ไม่เดาtimerขาเดียว |

---

## 15. Reset Rules Checklist

ทดสอบด้วย Manual + AutoNewCycle OFF

Clear State หมายถึงเคลียร์ operational round state
ไม่ใช่ลบ EQ/Refill/Realized/History หรือ state file ทั้งหมด

| ID | Status | Action Step | Expected Result |
|---|---|---|---|
| RS-01 | [ ] | คู่เต็ม Close All | Pos0 OR0 TT=EQ ไม่ rehedgeคืน |
| RS-02 | [ ] | ขาหนึ่งหาย timerนับ กดCloseAll | ปิดอีกขาและยกเลิกทั้งtimer |
| RS-03 | [ ] | ทั้งสองว่างแต่รอเติม กดCloseAll | disarmแม้ไม่มีไม้ |
| RS-04 | [ ] | ตรวจJSONหลังreset | armed/wait/intentfalse; timestampsเคลียร์ตามกติกา |
| RS-05 | [ ] | รอเกิน300s+restartหลังCloseAll | ไม่มี timer/intentเก่าปลุกคู่ |
| RS-06 | [ ] | RRถึงเป้า Re-Hedge ON | ปิดครบ/disarm ไม่เติมรอบเดิม |
| RS-07 | [ ] | RestartหลังRRจบ | ไม่มีคืนคู่เก่า/EQไม่ซ้ำ |
| RS-08 | [ ] | เปิดคู่ใหม่หลังReset | Peak/Timerรอบใหม่ ไม่ใช้เก่า |
| RS-09 | [ ] | เทียบEQหลังReset | ผลปิดถูก ไม่ย้อนทุนจำลองเริ่มต้น |

หมายเหตุ RS-04:
แยกผล "ไม่มีเปิดกลับ" กับ "ข้อมูล timer ถูกล้างครบ"
ห้ามรวมสองอย่างเป็น PASS เดียว

---

## 16. Known Issues / Pending Fixes

### 16.1 Confirmed source gaps — ยังไม่ใช่ Runtime FAIL ที่ผู้ใช้รายงาน

| ID | Type | Finding | Related tests | Status |
|---|---|---|---|---|
| KI-001 | Source-confirmed reset gap | StopReHedge() ปิด flags และ intent_since แต่ยังไม่ตั้ง m_buy_since/m_sell_since เป็น0; FinishReHedgeIntent(filled) ก็ปิด wait flag แต่เก็บ timestampเดิม | RS-04 | Pending decision/patch หลังรวบยอด |
| KI-002 | Functional gap | Auto-Lot มี Inputs/switch แต่ Execution ยังใช้ InpStartLot | ตรวจแยกจาก checklist ฟีเจอร์ปัจจุบัน | Not implemented |
| KI-003 | Validation gap | Integration ล่าสุดยังไม่มีผลครบชุด | ทุกข้อที่ [ ] | Pending test |
| KI-004 | Fault coverage gap | Crash/intent window ยังไม่มีหลักฐานตรวจรับ | P4-14/P4-15 | Pending test |

KI-001:
การคง timestamp ขณะ wait=false ไม่ได้ยืนยันว่าจะเปิดกลับผิด
แต่ไม่ตรงการ "เคลียร์ Timer fields 100%" ที่กำหนดไว้
ห้ามประกาศ RS-04 ผ่านโดยไม่แยกสองประเด็นนี้
ยังไม่ได้แก้ใน current commit

### 16.2 Design limitations — ไม่ใช่บั๊กโดยอัตโนมัติ

- Peak ช่วง offline/unobserved ไม่สามารถสร้างย้อนหลังได้
- Trailing/RR ฝั่ง EA ไม่ทำงานเมื่อ EA ไม่รัน
- Recovery Init failure ไม่ใช่ EA safe-lock ที่ยังดูแล Risk อยู่
- บาง runtime intent mismatch ออกจาก loopก่อน Risk
- ยังไม่รองรับ RETURN-only filling
- Save checksum/backup ไม่รับประกันทุกกรณีไฟดับ
- InitialRisk เป็นฐาน RR ไม่ใช่ cumulative loss cap
- Re-Hedge ต่อเนื่องมีค่าใช้จ่ายและความเสี่ยงสะสม
- Realized PnL accounting อาจต้องตรวจรายการ fee แยกของโบรกเกอร์
- Snapshot/parser มีขนาดและจำนวนIDจำกัด
- ไม่มี Trailing/Re-Hedge toggleเฉพาะบน Panel
- ไม่ได้สร้างระบบ Telemetry/Analytics ใหม่ในโปรเจกต์นี้
- ห้ามดึงระบบ log/analytics ของโปรเจกต์อื่นมาปะปนว่า implementแล้ว

### 16.3 Runtime FAIL register

ยังไม่มีรายการ Runtime FAIL ของชุดฟีเจอร์ล่าสุดที่ผู้ใช้ส่งกลับ

| Failure ID | Test ID | Actual behavior | Evidence | Suspected module | Fix batch | Status |
|---|---|---|---|---|---|---|
| — | — | รอผลผู้ใช้ | — | — | — | Pending |

รูปแบบเพิ่มรายการ:

- Failure ID:
- Test ID:
- Commit:
- .set:
- Symbol/Magic:
- Server time:
- Position/Deal/Order IDs:
- Expected:
- Actual:
- Log excerpt:
- State before:
- State after:
- Environment issue or Logic issue:
- Fix:
- Retest:
- Regression tests:

ห้ามใช้ "suspected" เป็น "confirmed root cause" โดยไม่มีหลักฐาน

---

## 17. Final Acceptance Gate

ยังไม่ใช้เงินจริงหากข้อสำคัญเป็น [-] หรือ [ ]:

- P2-04 / RH-07: ไม่เปิดซ้ำ
- P3-01 / P3-06: Hard SL และ SLไม่ถอย
- P4-02 / P4-05 / P4-14: Recoveryไม่ duplicate
- TR-05 / TR-06: Profit Guard/Peak
- RH-04 / RH-05 / RH-11: เติมฝั่งถูกหลังครบเวลา
- RS-02 / RS-05 / RS-06: Resetไม่มีรอบเก่ากลับมา

Compile baseline ไม่ใช่ release acceptance

---

### 17.1 Latest UI Readability Extension

Updated: 2026-10-08

Base state:

- Git baseline ที่ตรวจล่าสุด: 98e12e9
- Tooltip Patch ก่อนหน้า: [*] Compile ผ่านตามรายงานผู้ใช้
- Tooltip Runtime/hover ครบชุด: [ ]
- Readable Labels + Thai Inputs Patch: ส่งโค้ดแล้ว
- Compile ของ Readable Labels + Thai Inputs: [ ]
- New commit ของ UI ล่าสุด: ยังไม่ระบุ

ส่วนนี้เป็นสถานะ UI ล่าสุด
หากหัวข้อ Tooltip รุ่นก่อนยังเขียน Compile [ ] ให้ใช้อ้างอิงตามส่วนนี้
การ Compile ผ่านไม่ใช่การยืนยัน Hover/Resize/Recovery ผ่าน

Panel mapping:

| Display name | Object ID | Data source | Meaning |
|---|---|---|---|
| Equity | EQ | accounting.Balance() | VirtualBalance หลังรับรู้ผลปิดแล้ว ไม่รวม Floating |
| Profit | OR | accounting.Floating() | Floating Profit + Swap ของสถานะ EA นี้ |
| Total | TT | accounting.Equity() | VirtualBalance + Floating หรือ EQ + OR |

ข้อสำคัญ:

- เปลี่ยนเฉพาะชื่อแสดง ไม่เปลี่ยนสูตรบัญชี
- Equity บน Panel นี้ไม่ใช่ Account Equity ของ Terminal
- Profit ไม่ใช่กำไรสะสมที่ปิดแล้ว
- Total ไม่ใช่ TargetMoney หรือเป้าหมาย RR
- Object IDs EQ/OR/TT ยังเดิมเพื่อให้ Layout/Tooltip ทำงานต่อ
- Inputs มี Comments ภาษาไทยครบ
- ชื่อตัวแปร/Enum/Default เดิมทั้งหมด
- ชื่อ input group เปลี่ยนเฉพาะข้อความแสดงเป็นไทย
- Strategy default ยังคง MODE_LOCK_PRICE
- Session 1–3 default ยังคง true
- Magic default ยังคง 998874
- ไม่มีการแก้ Trade/Risk/Strategy/Persistence
- ไม่มีไฟล์ .mqh ใหม่
- KI-001 Timer timestamp reset gap ยังไม่ได้แก้
- Auto-Lot ยังใช้ Fixed StartLot ห้ามกล่าวว่า implement แล้ว

UI Readability Checklist:

| ID | Status | Action Step | Expected Result |
|---|---|---|---|
| UI-RD-01 | [ ] | เปิด Panel ขนาดปกติ | แสดง Equity / Profit / Total ไม่ใช่ EQ / OR / TT |
| UI-RD-02 | [ ] | เทียบตัวเลขก่อน/หลัง Patch | ค่าและสูตร Accounting เดิมไม่เปลี่ยน |
| UI-RD-03 | [ ] | Hover Metric แต่ละช่อง | Tooltip ใช้ชื่อเต็มและนิยามตรงค่าจริง |
| UI-RD-04 | [ ] | Resize/Minimize/Restore | ชื่อเต็มไม่ซ้อนช่องอื่น; พับ/ขยายยังทำงาน |
| UI-RD-05 | [ ] | เปิด Inputs | ทุก Input มีคำอธิบายไทย กลุ่มอ่านเข้าใจง่าย |
| UI-RD-06 | [ ] | เทียบ .set/ค่าตั้งเดิม | Strategy, Sessions, Magic และตัวเลขไม่เปลี่ยน |
| UI-RD-07 | [ ] | โหลด snapshot ด้วย Inputs เดิม | ไม่เกิด Settings mismatch จากการเปลี่ยน Comments |
| UI-RD-08 | [ ] | ตรวจคำอธิบาย Auto-Lot/RR/Trailing | ไม่อ้าง Auto-Lotทำงาน ไม่ตี RRเป็น%ทุน ไม่ตี Trailingเป็นเลื่อนSL |

Update after compile/test:

- Compile result:
- Compile duration:
- UI runtime result:
- New commit:
- Fail IDs:
- Evidence:

---

## 18. Next Work / AI Resume Instructions

### Immediate next action

1. รอผล Master Integration Test รวมจากผู้ใช้
2. เก็บเฉพาะ [-] และข้อที่ยังพิสูจน์ไม่ได้
3. ตรวจ Commit/.set/Log/state ที่ตรงกัน
4. แยก Environment กับ Logic
5. จัดกลุ่ม root causes
6. ส่ง Mini-Batch FIND/REPLACE ในแชต
7. Compileรวม
8. Retestข้อFAILและRegressionที่เกี่ยวข้อง
9. อัปเดต HANDOFF และ Commitเมื่อจบ milestone

### Do not do

- ไม่ประกาศ Phase 3/4 Runtimeผ่านครบจาก Compileอย่างเดียว
- ไม่ติ๊ก [*] ให้อัตโนมัติ
- ไม่ลบ stateเพื่อซ่อนRecoveryError
- ไม่ resetทุนโดยเงียบ
- ไม่ใช้ beginBasketใหม่ตอนเติมขา
- ไม่ปลด Open guardทั้งหมด
- ไม่ mergeสามStrategyเข้าด้วยกัน
- ไม่เปลี่ยน Timer300เป็นสัญญาณLock
- ไม่ให้ CloseAll/RRเติมคู่รอบเดิมเอง
- ไม่เพิ่ม Auto-Lot/Martingale โดยตีความเอง
- ไม่ขอSourceทั้งชุดเมื่อGitมีข้อมูล
- ไม่สร้างไฟล์ดาวน์โหลด

### Handoff summary for the next AI

โปรเจกต์นี้เป็น MT5 Portable EA แบบ8โมดูล Includeอยู่ข้างEA
ล่าสุด98e12e9 Compileผ่าน0errors0warnings2257ms
มีManual/TimeoutHedge/Lockแยก, HardSL, Fixed/DynamicBE,
BasketRR, VirtualAccounting, FlatJSONPersistence,
ResponsivePanel, TrailingTPแยกPosition+ProfitGuard,
และAutoReHedgeTimerแยกฝั่ง

ยังรอIntegrationTestรวม
Auto-LotยังFIXED LOT
มีSource-confirmed Timer timestamp reset gapที่KI-001
ห้ามบอกRuntimeผ่านทั้งหมด
ให้ตรวจGit/หลักฐานแล้วรวบยอดPatchตามผล[-]ของผู้ใช้

---

## 19. Change Log

| Date | Change | Validation |
|---|---|---|
| 2026-10-07 | Foundations + Manual Native Trade | Phase1/2 runtimeเดิมผ่านตามผู้ใช้ |
| 2026-10-07 | Risk/Strategy + Responsive UI | Compileผ่าน; Runtimeเบื้องต้น |
| 2026-10-08 | Phase4 Persistence/Recovery/Timeout | Compileผ่าน |
| 2026-10-08 | Trailing TP + Profit Guard + Auto Re-Hedge | Compileผ่าน2257ms |
| 2026-10-08 | HANDOFFเริ่มต้น + Master Checklist | Documentation; รอIntegration results |

Update procedure:

- เปลี่ยน Last updated
- เปลี่ยน current commitเมื่อมีcommitใหม่
- เก็บcompileผลจริง
- เปลี่ยนChecklistเฉพาะข้อที่มีหลักฐาน
- ย้ายRuntimeFAILลงregister
- ระบุfixed commitและretestผล
- ไม่ลบประวัติFAILเพื่อให้เอกสารดูผ่าน