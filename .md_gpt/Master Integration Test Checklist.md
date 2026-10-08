ได้ครับ นี่คือ **Master Integration Test Checklist** สำหรับ Phase 1–4 + Trailing TP + Auto Re-Hedge ใช้เป็นรอบตรวจรวมชุดเดียว และส่งกลับเฉพาะข้อที่ `[X]` เพื่อรวบยอดแก้ได้เลยครับ

Step Target ของรอบนี้: ยืนยันว่า Execution, Risk, บัญชี, Recovery และการเติม Hedge ทำงานร่วมกันตาม `.set` โดยไม่เปิดซ้ำ ไม่สูญเสียสถานะ และไม่ปลุก Timer ของรอบที่ปิดไปแล้ว

## วิธีบันทึกผล

ช่อง Status ของทุกข้อเริ่มเป็น `[]` แล้วเปลี่ยนเป็น:

- `[✓]` = ผ่าน พร้อมหลักฐาน
- `[X]` = ไม่ผ่าน
- `[—]` = ยังไม่ได้จำลอง / หลักฐานไม่พอ — ไม่นับเป็นผ่าน

เก็บชื่อ `.set`, Magic, เวลา Server และ Ticket ที่เกี่ยวข้องไว้ด้วย ไม่ใช้แค่ “ไม่มี Error Log” เป็นหลักฐานว่าทำงานถูกต้อง

## เตรียมรอบทดสอบ

ใช้ MT5 Demo แบบ Hedging สำหรับ EA ชุดนี้ ส่วน Visual Tester ใช้ช่วยจำลองราคาในชุด BE/Trailing ได้ แต่การปิดโปรแกรม–เปิดกลับและไฟล์ Recovery ควรตรวจบน Demo ด้วย เพราะ Tester มี File Sandbox แยกจาก Terminal ครับ [mql5](https://www.mql5.com/en/book/automation/tester)

### ค่าตั้งพื้นฐานสำหรับแยกทดสอบ

| ชุดตรวจ | ค่าตั้งสำคัญ |
|---|---|
| Manual / บัญชี / Recovery | `MODE_MANUAL_FREE`, `AutoNewCycle=false`, `Persistence=true` |
| BE | RR OFF, Trailing TP OFF, Auto Re-Hedge OFF ก่อนเริ่ม Basket |
| Basket RR | RR ON, Trailing TP OFF, Auto Re-Hedge OFF ก่อนเริ่ม Basket |
| Trailing TP | RR OFF, Trailing TP ON, Step = 500; ปิด BE หากต้องการแยกสาเหตุการปิด |
| Auto Re-Hedge | เริ่มจาก Hedge B1 S1, Auto Re-Hedge ON, Timeout = 300 |
| Reset Rules | Manual, AutoNewCycle OFF, Auto Re-Hedge ON |
| Strategy Isolation | `.set` แยก Manual / Timeout / Lock ชัดเจน |

ข้อควรทำก่อนเริ่ม:

1. สำรองชุดโค้ด, `.set`, `state.json` และ `.bak`
2. จด Commit ของชุดที่ Compile ผ่านล่าสุด
3. เริ่มแต่ละกลุ่มด้วย Basket ว่าง หรือใช้ Magic ทดสอบแยก
4. เปลี่ยน Inputs/`.set` เมื่อ Basket ว่างเท่านั้น
5. ตั้งระยะ SL/BE ให้โบรกเกอร์อนุญาต ไม่ลดจนติด Stops Level
6. ใช้เวลา Server ใน Log วัด 300 วินาที ไม่ใช้เวลาหน้าจอคอมพิวเตอร์แทน

***

## Phase 1 — Config, Runtime State และ Virtual Accounting

| ID | Status | Action Step | Expected Result ที่ต้องเห็น |
|---|---|---|---|
| P1-01 | [] | เริ่มด้วย Magic ใหม่ ไม่มี state และไม่มีไม้ | `Cycle: IDLE`, Positions = 0; EQ = Base Capital, OR = 0, TT = EQ; Log `Fresh virtual account` |
| P1-02 | [] | ตั้ง Base Capital = 0 แล้วโหลด | Init ถูกปฏิเสธพร้อม Config Error; ไม่มีคำสั่งเปิด |
| P1-03 | [] | เปิด Trailing TP แต่ตั้ง Step ≤ 0 | Init ถูกปฏิเสธ; แจ้ง `TrailingStepPoints must be positive` |
| P1-04 | [] | เปิด Auto Re-Hedge แต่ตั้ง Timeout ≤ 0 | Init ถูกปฏิเสธ; แจ้งว่า Timeout ต้องเป็นบวก |
| P1-05 | [] | กด Refill 2 ครั้ง ก่อนเทรด | Ref = 20.00 (2) เมื่อ Amount = 10; EQ เพิ่มจาก 50 เป็น 70; OR ยัง 0 |
| P1-06 | [] | เปิดไม้แล้วเทียบ EQ / OR / TT | TT = EQ + OR; OR ตรงกับสถานะของ EA นี้ ไม่รวมไม้ต่าง Magic/Symbol |
| P1-07 | [] | ปิดไม้ผ่าน Terminal แล้วรออัปเดต | EQ รับ Profit + Commission + Swap + Fee ของ Deal ตามที่ติดตาม; OR ของไม้ที่ปิดหายไป |
| P1-08 | [] | โหลด EA ซ้ำหลังปิดไม้ | ผลปิดเดิมไม่ถูกนับซ้ำ; EQ ไม่เพิ่ม/ลดอีกรอบจาก Deal เดิม |

***

## Phase 2 — Manual Execution, Single Basket และ Panel

| ID | Status | Action Step | Expected Result ที่ต้องเห็น |
|---|---|---|---|
| P2-01 | [] | Basket ว่าง กด BUY | เปิด Buy 1 ไม้; Log คำสั่งสำเร็จ; `IDLE → OPENING → ACTIVE` |
| P2-02 | [] | ปิดครบ แล้วกด SELL | เปิด Sell 1 ไม้ ไม่มี Buy แทรก |
| P2-03 | [] | Basket ว่าง กด HEDGE OPEN | เปิด Buy 1 + Sell 1; Positions = 2; ไม่อ้างว่าเปิดครบหากขาหนึ่งถูกปฏิเสธ |
| P2-04 | [] | กด BUY / SELL / HEDGE OPEN ซ้ำขณะมี Basket | ถูก Reject; ไม่มี B2/S2 หรือ Basket ใหม่ |
| P2-05 | [] | เลือก Lock และตั้ง Session นอกเวลาปัจจุบัน แล้วกด Manual HEDGE OPEN | เปิดทันทีโดยไม่รอ Session/Lock/Timeout แต่ยังผ่าน Risk และ Execution Guard |
| P2-06 | [] | ปิด Algo Trading แล้วกดเปิด | ไม่มีไม้ใหม่; Log แจ้งสิทธิ์เทรดถูกปิด ไม่รายงานสำเร็จปลอม |
| P2-07 | [] | ตั้ง Lot ต่ำกว่า Minimum ก่อนเริ่มรอบ | ปฏิเสธคำสั่ง ไม่เพิ่ม Lot ขึ้นเองโดยเงียบ ๆ |
| P2-08 | [] | มีไม้ของ EA และไม้ต่าง Magic แล้วกด CLOSE ALL | ปิดเฉพาะ Symbol/Magic ของ EA นี้ ไม้ต่างเจ้าของไม่ถูกปิด |
| P2-09 | [] | ปิด Hedge ขาหนึ่งผ่าน Terminal | Positions เหลือ 1; บัญชีรับ Deal; ไม่ถือว่าปิด Basket ครบ |
| P2-10 | [] | พับ Panel แล้วขยายกลับ / ย่อ Chart | ปุ่มซ่อนจริงขณะพับ, ขนาดปรับตาม Chart, ON ตัวหนังสือดำ; ตัวเลขและสวิตช์ไม่เปลี่ยนจากการพับ |

***

## Phase 3 — Hard SL, BE, Basket RR และ Strategy Isolation

### Core Risk Engine

| ID | Status | Action Step | Expected Result ที่ต้องเห็น |
|---|---|---|---|
| P3-01 | [] | เปิด Hard SL แล้วเปิด BUY และ SELL แยกรอบ | Terminal มี SL ถูกฝั่ง: Buy ต่ำกว่าราคาเปิด, Sell สูงกว่า; ไม่เปิดไม้เปลือยโดยตัด SL ทิ้ง |
| P3-02 | [] | ตั้งระยะ SL ที่โบรกเกอร์ไม่อนุญาต | ปฏิเสธการเปิดพร้อม Log; ไม่ขยาย SL หรือส่งซ้ำแบบไม่มี SL |
| P3-03 | [] | ตรวจช่อง TP ใน Terminal | แยกให้ถูก: ชุดนี้ RR/Trailing TP ปิดผ่าน EA ไม่จำเป็นต้องมี Server TP; TP = 0 ไม่ใช่ FAIL โดยตัวมันเอง |
| P3-04 | [] | RR OFF, เลือก Fixed BE แล้วให้กำไรถึง Trigger | SL ย้ายตาม `Trigger × LockPercent`; ไม่เลื่อนต่อเมื่อกำไรเพิ่ม |
| P3-05 | [] | RR OFF, เลือก Dynamic BE แล้วให้กำไรผ่านขั้น 10 Points | SL เลื่อนตามสูตรที่อนุมัติ หากราคา Tick/ระยะโบรกเกอร์อนุญาต; Log `Modify SL` |
| P3-06 | [] | หลัง BE เลื่อน ให้ราคาย่อตัว | SL ไม่ย้อนกลับไปเพิ่มความเสี่ยง |
| P3-07 | [] | เปลี่ยน Dynamic เป็น Fixed หลัง SL เลื่อน | ไม่ดึง SL กลับลง/ขึ้นไปยังระดับ Fixed ที่แย่กว่า |
| P3-08 | [] | เปิด RR ก่อนเริ่ม Basket แล้วให้ OR ถึง Target | Log `Basket RR reached`; ปิดทั้ง Basket; หากยังเหลือไม้ ต้องยังอยู่ในเจตนาปิด ไม่รายงานจบปลอม |
| P3-09 | [] | เปิด Hedge แล้วปิดขาหนึ่ง | Initial Risk/Target เดิมไม่ลดตาม Lot ที่เหลือ |
| P3-10 | [] | Lock Mode + Re-Lock ON แล้วให้โดน Hard SL | Lock เปลี่ยนเป็นราคาปิดจริงของ Deal ไม่ใช่ราคา SL ที่ตั้งไว้ก่อน Fill |
| P3-11 | [] | ปิดด้วย BE หรือ Manual Close | ไม่เกิด HardCut Re-Lock จากเหตุการณ์เหล่านี้ |

SL/TP ที่วางบน Server ยังทำงานแยกจาก Terminal แต่ BE และการสั่งปิดแบบ Helper ต้องอาศัย EA ทำงาน จึงต้องแยกสาเหตุการปิดจาก Deal/Log ให้ชัดครับ 

### สาม Strategy Modes ต้องไม่ปะปน

| ID | Status | Action Step | Expected Result ที่ต้องเห็น |
|---|---|---|---|
| P3-12 | [] | Manual Mode แล้วปล่อยผ่าน 300 วินาทีโดยยังไม่เปิดคู่ | ไม่เปิดเองจาก Timeout หรือ Lock |
| P3-13 | [] | Timeout Mode, Basket ว่าง เริ่มจับเวลาจน 300 วินาที | ไม่เปิดก่อนครบ; หลังครบและมี Tick ใหม่เปิด Hedge B1 S1 ไม่รอ Crossing |
| P3-14 | [] | Timeout Mode ขณะมี Basket | ไม่เปิด Basket ใหม่ทับของเดิม |
| P3-15 | [] | Lock Mode กด Lock แล้วให้ราคาข้ามระดับ | เปิดตาม Trigger/Direction; ไม่มี Timeout เปิดแทรก |
| P3-16 | [] | ราคาค้างเลยระดับหลังเปิดแล้ว | ไม่ยิงซ้ำเพราะยังอยู่เลยระดับ |
| P3-17 | [] | Lock Mode + Session ON แล้ว Crossing นอกเวลา | ไม่เปิดอัตโนมัติ แต่ Risk ยังดูแลไม้เดิม |
| P3-18 | [] | เกิด Crossing นอก Session แล้วราคาอยู่นอกระดับเมื่อเข้า Session | ไม่ Replay Crossing เก่าทันที ต้องเกิด Crossing ใหม่ |
| P3-19 | [] | Session OFF แล้ว Crossing ใหม่ | ข้าม Filter เวลา แต่ยังต้องผ่าน Lock Trigger |
| P3-20 | [] | AutoNewCycle OFF แล้วปิดครบ | ไม่เริ่มรอบทั่วไปซ้ำเอง; แยกจาก Re-Lock และ Auto Re-Hedge ที่มีสวิตช์ของตัวเอง |

***

## Phase 4 — Persistence และ State Recovery

### Snapshot และบัญชี

| ID | Status | Action Step | Expected Result ที่ต้องเห็น |
|---|---|---|---|
| P4-01 | [] | Refill แล้วถอด/แนบ EA โดยใช้ Inputs เดิม | Ref, จำนวนครั้ง, EQ และสวิตช์ที่บันทึกกลับมาเท่าเดิม |
| P4-02 | [] | มี Basket แล้วปิด MT5 ตามปกติ เปิดกลับ | ไม่เปิดเพิ่ม; Positions ตรง Terminal; OR คำนวณใหม่; Initial Risk เดิม |
| P4-03 | [] | หลัง Dynamic BE เลื่อน ปิด/เปิด MT5 | ไม่ตั้ง SL กลับระดับเดิม และไม่คำนวณ Initial Risk จาก SL ที่เลื่อนแล้ว |
| P4-04 | [] | ถอด EA → ปิดไม้ผ่าน Terminal → แนบกลับ | Replay Deal ที่เกิดช่วงหยุด; EQ รับครั้งเดียว; ไม้ที่ปิดไม่เหลือใน OR |
| P4-05 | [] | ทำ P4-04 แล้วโหลดซ้ำ 2–3 ครั้ง | EQ คงเดิม ไม่ Replay ผลปิดซ้ำ |
| P4-06 | [] | เปลี่ยน `.set` เมื่อ Basket ว่าง | บัญชีเดิมอยู่; ใช้ Inputs ของ `.set` ใหม่; Log แจ้ง Flat recovery |
| P4-07 | [] | เปลี่ยนค่าตั้งที่ถูกตรวจ ขณะมี Basket | Init ปฏิเสธพร้อมข้อความ Inputs changed; ไม่เขียนบัญชีเริ่มต้นทับ snapshot |
| P4-08 | [] | แนบ EA อีกตัวด้วย Account/Symbol/Magic เดียวกัน | ตัวที่สองไม่ถือ File Lock เดียวกัน; ไม่เขียน state แข่งกัน |

### เน็ตหลุด, ไฟล์เสีย และ Intent

ทำชุดไฟล์เสียบนสำเนาสภาพแวดล้อม Demo หรือหลังสำรองครบ ห้ามแก้ไฟล์ขณะ EA กำลังเขียนอยู่

| ID | Status | Action Step | Expected Result ที่ต้องเห็น |
|---|---|---|---|
| P4-09 | [] | ตัดเน็ตระหว่างมีไม้ แล้วเชื่อมกลับ | ไม่มีการเปิดซ้ำ; กระทบยอดสถานะ/History ที่กลับมาจริง; ไม่อ้างว่าติดตามราคาช่วงขาดเน็ตได้ |
| P4-10 | [] | ปิด MT5 แบบฉับพลันบน Demo แล้วเปิดกลับ | ใช้ snapshot ล่าสุดที่สมบูรณ์ + History Replay; ไม่ตั้ง EQ ใหม่หรือส่ง Intent เดิมซ้ำโดยไม่ตรวจ |
| P4-11 | [] | ทำไฟล์หลักเสีย โดยสำรองยังถูกต้อง | Log โหลด Backup; Replay History; ไม่กลืน Error แล้ว Fresh Start |
| P4-12 | [] | ย้ายทั้ง state และ backup ออกขณะมีไม้ แล้วโหลด | Recovery ถูกปฏิเสธ; ไม่มีเปิดเพิ่มหรือสร้าง Initial Risk เดาเอง |
| P4-13 | [] | คืน snapshot ที่ Position Identifier ไม่ตรงไม้จริง | Guard ปฏิเสธ Recovery ไม่จัดการไม้ผิดตัว |
| P4-14 | [] | จำลองหยุดหลังส่งเปิด/เติม แต่ก่อนบันทึกผล | ตรวจ Order/Position จริงก่อนส่งซ้ำ; หากยืนยันไม่ได้ต้องบล็อก ไม่เกิดไม้เบิ้ล |
| P4-15 | [] | จำลอง Close All/RR ปิดไม่ครบ แล้วรีสตาร์ต | คืนเจตนาปิดส่วนที่เหลือ ไม่เปลี่ยนกลับเป็นรอบเปิดใหม่ |

สำหรับ P4-14/P4-15 หากจับจังหวะ Fault ไม่ได้ ให้ `[—]` ไม่ใช่ `[✓]` การปิดโปรแกรมตามปกติอย่างเดียวไม่พิสูจน์ Recovery ของ Intent ที่ค้าง

หาก Recovery จบด้วย `INIT_FAILED` ให้ตรวจ Terminal ทันที เพราะ EA ไม่ได้รัน Risk Engine อยู่ เหลือคำสั่งคุ้มครองฝั่ง Server ที่มีอยู่เท่านั้น

***

## New Features — Trailing TP, Peak และ Profit Guard

ตั้ง RR OFF เพื่อไม่ให้ RR ปิด Basket ก่อนเห็น Trailing แยกขา

| ID | Status | Action Step | Expected Result ที่ต้องเห็น |
|---|---|---|---|
| TR-01 | [] | เปิด Trailing TP แล้วให้ BUY วิ่งขึ้น | Best Price เป็น Best Bid และไม่ลดลงตามราคาย่อ |
| TR-02 | [] | ให้ SELL วิ่งลง | Best Price เป็น Best Ask และไม่เพิ่มขึ้นตามราคาย้อน |
| TR-03 | [] | BUY ย้อนจาก Peak ครบ 500 Points ขณะ Profit > 0 | Log Trailing triggered; ปิดเฉพาะ BUY; SELL ไม่ถูก Close All |
| TR-04 | [] | SELL ย้อนครบระยะ ขณะ Profit > 0 | ปิดเฉพาะ SELL; BUY ไม่ถูกปิดตาม |
| TR-05 | [] | ย้อนครบระยะ แต่ `POSITION_PROFIT ≤ 0` | ไม่มีคำสั่งปิดจาก Trailing Helper |
| TR-06 | [] | บันทึก Peak แล้วปิด/เปิด MT5 | Peak เดิมถูกคืน ไม่ตั้งใหม่จาก Quote ปัจจุบัน |
| TR-07 | [] | ตัดเน็ตหลังบันทึก Peak แล้วเชื่อมกลับ | ใช้ Peak ที่เก็บไว้ตรวจ Quote ใหม่; ไม่แต่ง Peak จากช่วงขาดเน็ต |
| TR-08 | [] | เปิดไม้ทดแทนหลังไม้เดิมปิด | ไม้ใหม่มี Identifier/Peak ใหม่; ไม่รับ Peak เก่าของไม้ที่ปิดแล้ว |
| TR-09 | [] | `InpEnableTrailingTP=false` ก่อนเริ่มรอบ | ไม่มี Trailing Close; BE/SL/RR เดิมยังทำงานตามสวิตช์ |

Profit Guard ต้องพิสูจน์ว่า Profit เป็นบวกก่อนส่งคำสั่ง ไม่ใช้กำไรของ Deal หลังปิดเป็นหลักฐานเพียงอย่างเดียว เพราะราคา Execute อาจเปลี่ยนหลังคำขอถูกส่ง

***

## New Features — Auto Re-Hedge และ Single-Side Guard

ใช้ Timeout 300 วินาทีในการตรวจรับจริง สามารถใช้เวลาสั้นกว่านี้เพื่อ Smoke Test ได้ แต่ไม่นับแทนการยืนยันค่าจริง 300 วินาที

| ID | Status | Action Step | Expected Result ที่ต้องเห็น |
|---|---|---|---|
| RH-01 | [] | Auto Re-Hedge ON แล้วเปิด Hedge สำเร็จ | B1 S1 และ Log `Auto Re-Hedge armed` |
| RH-02 | [] | เริ่มด้วย BUY อย่างเดียว ไม่เคยเปิดเป็นคู่ | ไม่สร้าง SELL อัตโนมัติเพียงเพราะ Input Re-Hedge เปิดอยู่ |
| RH-03 | [] | ปิด BUY จากคู่เดิม แล้วจับเวลาจาก Deal Close | เหลือ B0 S1; เริ่ม BUY Timer; ไม่เปิด BUY ก่อนครบ 300 วินาที |
| RH-04 | [] | ครบ 300 วินาทีหลัง RH-03 | เปิด BUY หนึ่งไม้ กลับ B1 S1; SELL เดิมไม่ถูกเปิดซ้ำ |
| RH-05 | [] | ทำกลับกันโดยปิด SELL | เหลือ B1 S0 → ครบเวลาเติม SELL เท่านั้น |
| RH-06 | [] | ปิดขาจาก Trailing TP / Hard SL / BE แยกกรณี | ทุกกรณีเริ่ม Timer ของฝั่งที่หาย ไม่ต้องรอ Lock Crossing |
| RH-07 | [] | กดเปิดซ้ำ/มี Tick ถี่ตอนเติมสำเร็จ | ไม่เกิด B2 S1 หรือ B1 S2; ฝั่งที่มีแล้วไม่ถูกเติม |
| RH-08 | [] | ปิดบางส่วน แต่ Position ฝั่งนั้นยังอยู่ | ไม่ถือว่าฝั่งหาย ไม่เปิดไม้เติม |
| RH-09 | [] | ปิด BUY และ SELL คนละเวลา | Timer แยกตาม Deal ของแต่ละฝั่ง ไม่รีเซ็ตอีกฝั่ง |
| RH-10 | [] | ระหว่างรอเติม ทั้งสองฝั่งไม่มีไม้ | ไม่ให้ Timeout/Lock Strategy เปิด Basket ใหม่แทรก Re-Hedge เดิม |
| RH-11 | [] | ปิด/เปิด MT5 ระหว่างรอเติม | Timer เดิมกลับมา; เวลาที่ผ่านไม่เริ่มศูนย์; เติมเพียงฝั่งที่ยังขาด |
| RH-12 | [] | เติมหนึ่งขาแล้วตรวจ Risk | มี Hard SL ของขาใหม่; Initial Risk/Target เดิมไม่ถูก BeginBasket ใหม่ |
| RH-13 | [] | บล็อกสิทธิ์เทรดตอนครบเวลา แล้วเปิดสิทธิ์กลับ | คำสั่งไม่สำเร็จไม่กลายเป็นไม้ปลอม; ไม่ Spam เปิดทุก Tick; รอรอบ Retry ตามกติกา |
| RH-14 | [] | Auto Re-Hedge OFF ก่อนเริ่มรอบ | ขาปิดแล้วไม่ถูกเติม แม้ครบเวลา |
| RH-15 | [] | Re-Hedge ใน Lock Mode นอก Session | เติมคู่เดิมได้โดยไม่รอ Session/Lock แต่ไม่เพิ่ม Basket อื่น |
| RH-16 | [] | ใช้ snapshot เก่าก่อนเพิ่มฟีเจอร์ | คู่เต็มสามารถ Adopt ได้; ถ้าเหลือขาเดียว ห้ามแต่ง Timer ย้อนหลังจากการเดา |

***

## Reset Rules — CLOSE ALL และ Basket RR

“Clear State” ในชุดนี้หมายถึงล้างสถานะปฏิบัติการของรอบที่จบ ไม่ใช่ลบทุนจำลอง ประวัติ Deal หรือไฟล์บัญชีทั้งหมด

ตั้ง Manual + AutoNewCycle OFF เพื่อแยกการพิสูจน์ Reset ออกจากการเริ่มรอบใหม่โดยกลยุทธ์เดิม

| ID | Status | Action Step | Expected Result ที่ต้องเห็น |
|---|---|---|---|
| RS-01 | [] | มีคู่เต็ม กด CLOSE ALL ORDER | ปิดไม้ทั้งหมดของ EA; Positions = 0; OR = 0; TT = EQ; ไม่มีเติมกลับจาก Re-Hedge |
| RS-02 | [] | ปิดขาหนึ่งจน Timer กำลังนับ แล้วกด CLOSE ALL | ปิดขาที่เหลือ และยกเลิก Timer ทั้ง BUY/SELL |
| RS-03 | [] | ทั้งสองขาว่างแต่ Re-Hedge ยังรอ แล้วกด CLOSE ALL | ยกเลิกการดูแลคู่ แม้ตอนกดไม่มี Position ให้ปิด |
| RS-04 | [] | ตรวจ state หลัง RS-01–03 | `rh_armed=false`, Wait flags=false, Intent=false; เวลา Timer ที่ยกเลิกต้องถูกเคลียร์ตามกติกา Reset ไม่ใช่กลับมานับต่อ |
| RS-05 | [] | หลัง CLOSE ALL รอเกิน 300 วินาทีและรีสตาร์ต | ไม่มีการเติมจาก Timer/Intent ของรอบที่ปิดไปแล้ว |
| RS-06 | [] | เปิด RR + Auto Re-Hedge แล้วให้ Basket ถึง Target | RR ปิดทั้ง Basket และยกเลิก Re-Hedge; ไม่เติมทันทีหลังปิด RR |
| RS-07 | [] | รีสตาร์ตหลัง RR ปิดครบ | ไม่มี Timer/Intent เก่าปลุกคู่กลับ; EQ คงผลปิดและไม่ Replay ซ้ำ |
| RS-08 | [] | เปิด Hedge รอบใหม่หลัง Reset | เริ่ม Timer/Peak ของรอบใหม่ ไม่ใช้ Peak หรือขาที่ขาดจากรอบก่อน |
| RS-09 | [] | เทียบ EQ ก่อน/หลัง Reset | รับผลปิดตามจริง แต่ไม่ย้อน Base Capital/Refill/Realized กลับค่าเริ่มต้น |

หาก Timestamp เก่ายังคงอยู่ใน JSON แต่ Guard ปิดไว้ ให้บันทึกแยกสองผล: “ไม่มีการเปิดกลับ” กับ “เคลียร์ข้อมูล Timer ครบหรือไม่” อย่ารวมเป็น PASS เดียว เพราะคุณต้องการ Reset ทั้งพฤติกรรมและข้อมูลสถานะให้ครบ

## จุดผ่านขั้นต่ำก่อนใช้เงินจริง

ยังไม่ใช้เงินจริงหากข้อใดข้อหนึ่งต่อไปนี้เป็น `[X]` หรือ `[—]`:

- P2-04 / RH-07: Single Basket และไม่มี B2/S2
- P3-01 / P3-06: Hard SL ถูกฝั่งและ SL ไม่ถอย
- P4-02 / P4-05 / P4-14: Recovery ไม่เปิดซ้ำและไม่ลงบัญชีซ้ำ
- TR-05 / TR-06: Profit Guard และคืน Peak ถูกต้อง
- RH-04 / RH-05 / RH-11: เติมเฉพาะขาที่หายหลังครบเวลา
- RS-02 / RS-05 / RS-06: Close All/RR ไม่ทิ้ง Timer ที่กลับมาเปิดรอบเดิม

## รูปแบบส่งกลับเมื่อฟูลเทสต์เสร็จ

คัดลอกเฉพาะรายการ FAIL และรายการที่ยังตรวจไม่ได้:

```text
Commit:
MT5 Build:
Symbol / Magic:
.set ที่ใช้:

[X] RH-04
Action: ปิด BUY เวลา Server ...
Expected: ครบ 300 วิ เปิด BUY เท่านั้น
Actual: ...
Tickets: ...
Log ช่วงก่อน/หลังเหตุการณ์: ...

[X] RS-04
Actual state fields:
rh_armed=...
rh_buy_wait=...
rh_sell_wait=...
rh_buy_since=...
rh_sell_since=...
rh_intent=...

[—] P4-14
เหตุผล: ยังจับจังหวะหยุดหลังส่งคำสั่งไม่ได้

รายการอื่นที่ตรวจแล้ว: PASS
```

ส่ง `state.json` เฉพาะส่วนที่เกี่ยวข้องหรือ Snapshot ก่อน/หลังเหตุการณ์ได้ แต่ไม่ต้องส่ง Token หรือ Source ทั้งชุด จากนั้นเราจะจัดกลุ่มสาเหตุและแก้เป็น Mini-Batch เดียว พร้อมรันทวนข้อ FAIL และข้อที่เกี่ยวข้องครับ