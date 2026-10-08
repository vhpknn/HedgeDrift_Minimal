#ifndef HEDGEDRIFT_PANEL_ENGINE_MQH
#define HEDGEDRIFT_PANEL_ENGINE_MQH

#include "RuntimeState.mqh"
#include "AccountingEngine.mqh"

enum ENUM_HD_PANEL_ACTION
{
   HD_ACTION_NONE = 0,
   HD_ACTION_BUY,
   HD_ACTION_SELL,
   HD_ACTION_HEDGE,
   HD_ACTION_CLOSE,
   HD_ACTION_REFILL,
   HD_ACTION_LOCK,
   HD_ACTION_MODE,
   HD_ACTION_DIRECTION,
   HD_ACTION_BE_TYPE,
   HD_ACTION_HARD,
   HD_ACTION_BE,
   HD_ACTION_RR,
   HD_ACTION_SESSION,
   HD_ACTION_RELOCK
};

class CHDPanel
{
private:
   string m_prefix;

   bool m_collapsed;
   bool m_compact;
   double m_scale;
   int m_panel_width;
   int m_header_font;

   int m_last_chart_width;
   int m_last_chart_height;
   bool m_layout_dirty;

   int MetricWidth()
   {
      int padding = (int)MathRound(14.0 * m_scale);
      int gap = (int)MathMax(4.0, MathRound(8.0 * m_scale));

      return (int)MathMax(
         1.0,
         MathFloor((m_panel_width - 2.0 * padding - 2.0 * gap) / 3.0)
      );
   }

   string TooltipText(const string suffix)
   {
      if(suffix == "BG")
         return "แผงควบคุม EA นี้\nพับแผงได้โดยไม่หยุดระบบเทรดและควบคุมความเสี่ยง";

      if(suffix == "HEADER")
         return "ชื่อและเวอร์ชัน EA | สัญลักษณ์ที่เทรด | Magic Number\nใช้แยกสถานะของ EA นี้จากระบบอื่น";

      if(suffix == "STATE")
         return "โหมดปัจจุบัน | สถานะรอบการทำงาน | จำนวนสถานะที่เปิด\nนับเฉพาะ Symbol และ Magic ของ EA นี้";

      if(suffix == "CAP")
         return "Cap: ทุนจำลองตั้งต้น | Ref: ยอดเติมและจำนวนครั้ง\nLot: ขนาดที่ใช้เปิด ชุดนี้ยังเป็น Fixed Lot";

      if(suffix == "EQ")
         return "Equity: ยอดทุนจำลองหลังรับรู้ผลปิดแล้ว\nทุนตั้งต้น + ยอดเติม + ผลปิด ไม่รวมกำไรลอยตัว";

      if(suffix == "OR")
         return "Profit: กำไร/ขาดทุนลอยตัวของสถานะ EA นี้\nรวม Profit และ Swap ไม่ใช่กำไรสะสมที่ปิดแล้ว";

      if(suffix == "TT")
         return "Total: ทุนจำลองรวม = Equity + Profit\nมูลค่ารวมปัจจุบัน ไม่ใช่เป้ากำไร RR";

      if(suffix == "LOCKVALUE")
         return "ราคาอ้างอิงของ Lock Mode\nใช้ตรวจการข้ามระดับตามระยะที่ตั้งไว้";

      // Development-status row removed from the panel.

      if(suffix == "BUY")
         return "เปิด BUY ทันทีตาม Lot ที่ใช้งาน เมื่อ Basket ว่าง\nข้ามสัญญาณเข้า แต่ยังตรวจสิทธิ์เทรดและ Risk";

      if(suffix == "SELL")
         return "เปิด SELL ทันทีตาม Lot ที่ใช้งาน เมื่อ Basket ว่าง\nข้ามสัญญาณเข้า แต่ยังตรวจสิทธิ์เทรดและ Risk";

      if(suffix == "HEDGE")
         return "เปิด BUY และ SELL เป็นคู่ เมื่อ Basket ว่าง\nเป็นสองคำสั่งต่อกัน ไม่ใช่ธุรกรรมเดียว";

      if(suffix == "LOCK")
         return "ตั้ง Lock Price จากราคากึ่งกลาง Bid/Ask ปัจจุบัน\nเริ่มอ้างอิง Crossing ใหม่ ไม่เปิดไม้จากปุ่มนี้";

      if(suffix == "REFILL")
         return "เพิ่มทุนจำลอง " + DoubleToString(InpRefillAmount, 2) +
                " ตามค่าที่ตั้งไว้\nไม่เปลี่ยน Base Capital และไม่ใช่การฝากเงินจริง";

      if(suffix == "CLOSE")
         return "ปิดสถานะ EA นี้และยกเลิก Re-Hedge ของรอบเดิม\nไม่ลบทุน/ประวัติ และไม่ปิดสวิตช์ Auto New Cycle";

      if(suffix == "MODE")
         return "สลับ Manual / Timeout Hedge / Lock Crossing\nเปลี่ยนได้เมื่อไม่มีสถานะเปิดของ EA";

      if(suffix == "DIRECTION")
         return "ทิศทางของ Lock: BUY / SELL / BOTH / HEDGE\nไม่เปลี่ยนฝั่งของปุ่ม Manual หรือ Timeout Hedge";

      if(suffix == "BETYPE")
         return "เลือก Fixed BE หรือ Dynamic BE\nการเปลี่ยนประเภทไม่ดึง SL ถอยหลัง";

      if(suffix == "HARD")
         return "เปิด/ปิด Hard SL ที่ส่งไปยัง Server ตอนเปิดไม้\nเปลี่ยนได้เมื่อ Basket ว่าง ไม่ได้ลบ SL ของไม้เดิม";

      if(suffix == "BE")
         return "เปิด/ปิดการเลื่อน SL ตามกำไรและค่าที่ตั้งไว้\nปิดสวิตช์แล้วไม่ลบ SL ที่เคยเลื่อนไว้";

      if(suffix == "RR")
         return "เปิด/ปิดเป้ากำไรรวมจาก Initial Risk ของ Basket\nเปลี่ยนได้เมื่อว่าง ไม่ลดเป้าตาม BE หรือปิดบางขา";

      if(suffix == "SESSION")
         return "กรองเวลาเปิดอัตโนมัติเฉพาะ Lock Mode\nใช้เวลา Server ไม่บล็อก Manual หรือ Re-Hedge";

      if(suffix == "RELOCK")
         return "Hard SL เดิมใน Lock Mode ใช้ราคาปิดเป็น Lock ใหม่\nไม่รวม Manual Close หรือ SL ที่เลื่อนด้วย BE";

      if(suffix == "MINI")
      {
         if(m_scale < 0.65)
            return "กราฟเล็กเกินไปจึงพับแผงอัตโนมัติ\nขยายหน้าต่างกราฟเพื่อแสดงปุ่มทั้งหมด";

         if(m_compact)
            return "ขยายแผงควบคุม\nการพับแผงไม่ได้หยุดการเทรดหรือระบบ Risk";

         return "พับแผงให้เหลือแถบหัว\nEA และระบบ Risk ยังทำงานตามปกติ";
      }

      return "องค์ประกอบของแผงควบคุม HedgeDrift";
   }

   void ApplyTooltips()
   {
      if(StringLen(m_prefix) == 0)
         return;

      int total = ObjectsTotal(0, -1, -1);

      for(int i = total - 1; i >= 0; i--)
      {
         string object_name = ObjectName(0, i, -1, -1);

         if(StringFind(object_name, m_prefix) != 0)
            continue;

         string suffix =
            StringSubstr(object_name, StringLen(m_prefix));

         string tooltip = TooltipText(suffix);

         // Do not repeatedly reset an unchanged hover tooltip.
         if(ObjectGetString(0, object_name, OBJPROP_TOOLTIP) != tooltip)
         {
            ObjectSetString(
               0, object_name, OBJPROP_TOOLTIP, tooltip
            );
         }
      }
   }

   void SelectorStyle(const string suffix,
                      const color background,
                      const color foreground)
   {
      string name = Name(suffix);

      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, background);
      ObjectSetInteger(0, name, OBJPROP_COLOR, foreground);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, background);
   }

   void UpdateSelectorStyles()
   {
      // MODE: color represents the selected strategy.
      switch(g_hd.strategy)
      {
         case MODE_MANUAL_FREE:
            SelectorStyle("MODE", C'15,118,110', clrWhite);
            break;

         case MODE_TIMEOUT_HEDGE:
            SelectorStyle("MODE", C'245,158,11', clrBlack);
            break;

         case MODE_LOCK_PRICE:
            SelectorStyle("MODE", C'30,102,245', clrWhite);
            break;
      }

      // DIRECTION: same visual meaning as BUY / SELL / HEDGE.
      switch(g_hd.direction)
      {
         case DIR_BUY_ONLY:
            SelectorStyle("DIRECTION", C'30,102,245', clrWhite);
            break;

         case DIR_SELL_ONLY:
            SelectorStyle("DIRECTION", C'190,45,65', clrWhite);
            break;

         case DIR_BOTH:
            SelectorStyle("DIRECTION", C'0,110,120', clrWhite);
            break;

         case DIR_HEDGE:
            SelectorStyle("DIRECTION", C'136,57,239', clrWhite);
            break;
      }

      // BE TYPE: selected type, not the Auto BE ON/OFF switch.
      if(g_hd.be_type == BE_TYPE_FIXED)
         SelectorStyle("BETYPE", C'229,200,144', clrBlack);
      else
         SelectorStyle("BETYPE", C'137,180,250', clrBlack);
   }

   void StateStyle(const string suffix, const bool enabled)
   {
      string name = Name(suffix);

      ObjectSetInteger(0, name, OBJPROP_BGCOLOR,
         enabled ? C'166,227,161' : C'88,91,112');

      ObjectSetInteger(0, name, OBJPROP_COLOR,
         enabled ? clrBlack : clrWhite);
   }

   string FitLabel(const string text, const int available,
                   const int font_size)
   {
      double estimated_character_width =
         MathMax(1.0, font_size * 0.72);

      int limit =
         (int)MathFloor(available / estimated_character_width);

      if(limit <= 0)
         return "";

      if(StringLen(text) <= limit)
         return text;

      if(limit <= 3)
         return StringSubstr(text, 0, limit);

      return StringSubstr(text, 0, limit - 3) + "...";
   }

   string Name(const string suffix)
   {
      return m_prefix + suffix;
   }

   bool Common(const string name, const int x, const int y)
   {
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      return true;
   }

   bool Label(const string suffix, const int x, const int y,
              const color text_color, const int size)
   {
      string name = Name(suffix);

      if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
         return false;

      Common(name, x, y);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_COLOR, text_color);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 20);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
      return true;
   }

   bool Button(const string suffix, const string text,
               const int x, const int y,
               const color background, const color foreground)
   {
      string name = Name(suffix);

      if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0))
         return false;

      Common(name, x, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, 126);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, 30);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, background);
      ObjectSetInteger(0, name, OBJPROP_COLOR, foreground);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, C'69,71,90');
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 10);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      return true;
   }

   void Text(const string suffix, const string value)
   {
      string name = Name(suffix);
      string display = value;

      if(ObjectFind(0, name) >= 0 &&
         (ENUM_OBJECT)ObjectGetInteger(0, name, OBJPROP_TYPE) == OBJ_LABEL)
      {
         int font_size =
            (int)ObjectGetInteger(0, name, OBJPROP_FONTSIZE);

         int available = m_panel_width - 24;

         if(suffix == "HEADER")
            available -= 66;

         if(suffix == "EQ" || suffix == "OR" || suffix == "TT")
            available = MetricWidth();

         display = FitLabel(value, available, font_size);
      }

      ObjectSetString(0, name, OBJPROP_TEXT, display);
   }

public:
   void Layout()
   {
      int chart_width =
         (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);

      int chart_height =
         (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);

      if(chart_width <= 0 || chart_height <= 0)
         return;

      if(!m_layout_dirty &&
         chart_width == m_last_chart_width &&
         chart_height == m_last_chart_height)
         return;

      m_last_chart_width = chart_width;
      m_last_chart_height = chart_height;
      m_layout_dirty = false;

      // Keep margins and reduce footprint on narrower chart windows.
      double width_scale =
         MathMin((chart_width - 24.0) / 420.0,
                 chart_width / 900.0);

      double height_scale = (chart_height - 36.0) / 424.0;

      m_scale = MathMin(1.0, MathMin(width_scale, height_scale));
      m_scale = MathMax(0.01, m_scale);

      bool forced_compact = m_scale < 0.65;
      m_compact = m_collapsed || forced_compact;

      int left = 8;
      int top = 8;

      if(m_compact)
      {
         m_panel_width = (int)MathMin(280.0, chart_width - 16.0);
         m_panel_width = (int)MathMax(1.0, m_panel_width);
      }
      else
      {
         m_panel_width = (int)MathRound(420.0 * m_scale);
      }

      int panel_height =
         m_compact
         ? (int)MathMin(34.0, MathMax(1.0, chart_height - 16.0))
         : (int)MathRound(424.0 * m_scale);

      string background = Name("BG");

      ObjectSetInteger(0, background, OBJPROP_XDISTANCE, left);
      ObjectSetInteger(0, background, OBJPROP_YDISTANCE, top);
      ObjectSetInteger(0, background, OBJPROP_XSIZE, m_panel_width);
      ObjectSetInteger(0, background, OBJPROP_YSIZE, panel_height);
      ObjectSetInteger(0, background, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);

      string labels[] =
      {
         "HEADER", "STATE", "CAP",
         "EQ", "OR", "TT",
         "LOCKVALUE"
      };

      int label_y[] = {12, 40, 66, 92, 92, 92, 118};

      for(int i = 0; i < ArraySize(labels); i++)
      {
         string name = Name(labels[i]);

         int font_size = i == 0 ? 11 : 10;
         font_size = (int)MathMax(7.0, MathRound(font_size * m_scale));

         if(m_compact && i == 0)
            font_size = 9;

         if(i == 0)
            m_header_font = font_size;

         int label_x =
            left + (m_compact ? 10 : (int)MathRound(14.0 * m_scale));

         int metric_column = -1;

         if(labels[i] == "EQ") metric_column = 0;
         if(labels[i] == "OR") metric_column = 1;
         if(labels[i] == "TT") metric_column = 2;

         if(metric_column >= 0)
         {
            int gap =
               (int)MathMax(4.0, MathRound(8.0 * m_scale));

            label_x =
               left +
               (int)MathRound(14.0 * m_scale) +
               metric_column * (MetricWidth() + gap);
         }

         ObjectSetInteger(0, name, OBJPROP_XDISTANCE, label_x);

         ObjectSetInteger(0, name, OBJPROP_YDISTANCE,
            top + (m_compact ? 8 : (int)MathRound(label_y[i] * m_scale)));

         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);

         ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES,
            (!m_compact || i == 0) ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
      }

      string buttons[] =
      {
         "BUY", "SELL", "HEDGE",
         "LOCK", "REFILL", "CLOSE",
         "MODE", "DIRECTION", "BETYPE",
         "HARD", "BE", "RR",
         "SESSION", "RELOCK"
      };

      int button_font =
         (int)MathMax(7.0, MathRound(9.0 * m_scale));

      for(int i = 0; i < ArraySize(buttons); i++)
      {
         int column = i % 3;
         int row = i / 3;
         string name = Name(buttons[i]);

         ObjectSetInteger(0, name, OBJPROP_XDISTANCE,
            left + (int)MathRound((14.0 + column * 138.0) * m_scale));

         ObjectSetInteger(0, name, OBJPROP_YDISTANCE,
            top + (int)MathRound((146.0 + row * 44.0) * m_scale));

         ObjectSetInteger(0, name, OBJPROP_XSIZE,
            (int)MathRound(126.0 * m_scale));

         ObjectSetInteger(0, name, OBJPROP_YSIZE,
            (int)MathRound(30.0 * m_scale));

         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, button_font);

         ObjectSetInteger(0, name, OBJPROP_STATE, false);

         ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES,
            m_compact ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
      }

      string mini = Name("MINI");

      int mini_width =
         (int)MathMin(58.0, MathMax(1.0, m_panel_width - 8.0));

      int mini_height =
         (int)MathMin(22.0, MathMax(1.0, panel_height - 8.0));

      ObjectSetInteger(0, mini, OBJPROP_XDISTANCE,
         left + m_panel_width - mini_width - 4);

      ObjectSetInteger(0, mini, OBJPROP_YDISTANCE, top + 4);
      ObjectSetInteger(0, mini, OBJPROP_XSIZE, mini_width);
      ObjectSetInteger(0, mini, OBJPROP_YSIZE, mini_height);
      ObjectSetInteger(0, mini, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, mini, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
      ObjectSetInteger(0, mini, OBJPROP_STATE, false);

      ObjectSetString(0, mini, OBJPROP_TEXT,
         m_compact ? "Panel" : "_");

      ObjectSetInteger(0, mini, OBJPROP_ZORDER, 30);
      ObjectSetString(0, mini, OBJPROP_TOOLTIP, TooltipText("MINI"));

      ChartRedraw(0);
   }

   bool Create()
   {
      m_collapsed = false;
      m_compact = false;
      m_scale = 1.0;
      m_panel_width = 420;
      m_header_font = 11;
      m_last_chart_width = -1;
      m_last_chart_height = -1;
      m_layout_dirty = true;

      m_prefix = "HD_" + IntegerToString((long)InpMagicNumber) + "_";
      Destroy();

      string background = Name("BG");

      if(!ObjectCreate(0, background, OBJ_RECTANGLE_LABEL, 0, 0, 0))
         return false;

      Common(background, 10, 20);
      ObjectSetInteger(0, background, OBJPROP_XSIZE, 420);
      ObjectSetInteger(0, background, OBJPROP_YSIZE, 424);
      ObjectSetInteger(0, background, OBJPROP_BGCOLOR, C'24,24,37');
      ObjectSetInteger(0, background, OBJPROP_COLOR, C'69,71,90');
      ObjectSetInteger(0, background, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, background, OBJPROP_ZORDER, 0);

      bool ok = true;

      if(!Label("HEADER", 24, 32, C'249,226,175', 11)) ok = false;
      if(!Label("STATE", 24, 60, C'205,214,244', 10)) ok = false;
      if(!Label("CAP", 24, 86, C'205,214,244', 10)) ok = false;
      if(!Label("EQ", 24, 112, C'137,180,250', 10)) ok = false;
      if(!Label("OR", 162, 112, C'137,180,250', 10)) ok = false;
      if(!Label("TT", 300, 112, C'137,180,250', 10)) ok = false;
      if(!Label("LOCKVALUE", 24, 138, C'205,214,244', 10)) ok = false;

      if(!Button("BUY", "BUY", 24, 192,
                 C'30,102,245', clrWhite)) ok = false;

      if(!Button("SELL", "SELL", 162, 192,
                 C'230,69,83', clrWhite)) ok = false;

      if(!Button("HEDGE", "HEDGE OPEN", 300, 192,
                 C'136,57,239', clrWhite)) ok = false;

      if(!Button("LOCK", "LOCK PRICE", 24, 236,
                 C'14,116,144', clrWhite)) ok = false;

      if(!Button("REFILL", "REFILL", 162, 236,
                 C'22,101,52', clrWhite)) ok = false;

      if(!Button("CLOSE", "CLOSE ALL", 300, 236,
                 C'229,200,144', C'17,17,27')) ok = false;

      if(!Button("MODE", "MODE", 24, 280,
                 C'49,50,68', C'205,214,244')) ok = false;

      if(!Button("DIRECTION", "DIRECTION", 162, 280,
                 C'49,50,68', C'205,214,244')) ok = false;

      if(!Button("BETYPE", "BE TYPE", 300, 280,
                 C'49,50,68', C'205,214,244')) ok = false;

      if(!Button("HARD", "HARD SL", 24, 324,
                 C'49,50,68', C'205,214,244')) ok = false;

      if(!Button("BE", "AUTO BE", 162, 324,
                 C'49,50,68', C'205,214,244')) ok = false;

      if(!Button("RR", "RR TARGET", 300, 324,
                 C'49,50,68', C'205,214,244')) ok = false;

      if(!Button("SESSION", "SESSION", 24, 368,
                 C'49,50,68', C'205,214,244')) ok = false;

      if(!Button("RELOCK", "RE-LOCK", 162, 368,
                 C'49,50,68', C'205,214,244')) ok = false;

      if(!Button("MINI", "_", 360, 24,
                 C'49,50,68', clrWhite))
         ok = false;

      if(!ok)
      {
         Destroy();
         return false;
      }

      Layout();
      ApplyTooltips();

      ChartRedraw(0);
      return true;
   }

   void Destroy()
   {
      if(StringLen(m_prefix) > 0)
         ObjectsDeleteAll(0, m_prefix);

      ChartRedraw(0);
   }

   void Update(CHDAccounting &accounting)
   {
      Layout();

      string header = m_compact
         ? "HD " + string(HD_VERSION) + " | " + _Symbol
         : "HedgeDrift " + string(HD_VERSION) + " | "
           + _Symbol + " | #" + IntegerToString((long)InpMagicNumber);

      Text("HEADER", header);

      string mode = g_hd.strategy == MODE_MANUAL_FREE
         ? "MANUAL"
         : (g_hd.strategy == MODE_TIMEOUT_HEDGE ? "TIMEOUT" : "LOCK");

      Text("STATE",
           mode + " | Cycle: " + HD_CycleName(g_hd.cycle)
           + " | Pos: " + IntegerToString(accounting.PositionCount()));

      Text("CAP",
           "Cap: " + DoubleToString(accounting.BaseCapital(), 2)
           + " | Ref: " + DoubleToString(accounting.RefillTotal(), 2)
           + " (" + IntegerToString(accounting.RefillCount()) + ")"
           + " | Lot: " + DoubleToString(InpStartLot, 4));

      Text("EQ", "Equity: " + DoubleToString(accounting.Balance(), 2));
      Text("OR", "Profit: " + DoubleToString(accounting.Floating(), 2));
      Text("TT", "Total: " + DoubleToString(accounting.Equity(), 2));

      Text("LOCKVALUE",
           "Lock Price: "
           + (g_hd.lock_price > 0.0
              ? DoubleToString(g_hd.lock_price, _Digits)
              : "Not set"));

      Text("REFILL", "REFILL " + DoubleToString(InpRefillAmount, 2));

      Text("MODE", "MODE: " + mode);

      string direction = "BOTH";
      if(g_hd.direction == DIR_BUY_ONLY) direction = "BUY";
      if(g_hd.direction == DIR_SELL_ONLY) direction = "SELL";
      if(g_hd.direction == DIR_HEDGE) direction = "HEDGE";

      Text("DIRECTION", "DIR: " + direction);
      Text("BETYPE", g_hd.be_type == BE_TYPE_FIXED
                    ? "BE: FIXED" : "BE: DYNAMIC");

      Text("HARD", g_hd.hard_cut_loss ? "HARD SL: ON" : "HARD SL: OFF");
      Text("BE", g_hd.auto_be ? "AUTO BE: ON" : "AUTO BE: OFF");
      Text("RR", g_hd.rr_target ? "RR: ON" : "RR: OFF");
      Text("SESSION", g_hd.session_filter ? "SESSION: ON" : "SESSION: OFF");
      Text("RELOCK", g_hd.cut_loss_relock ? "RE-LOCK: ON" : "RE-LOCK: OFF");

      StateStyle("HARD", g_hd.hard_cut_loss);
      StateStyle("BE", g_hd.auto_be);
      StateStyle("RR", g_hd.rr_target);
      StateStyle("SESSION", g_hd.session_filter);
      StateStyle("RELOCK", g_hd.cut_loss_relock);

      UpdateSelectorStyles();
      ApplyTooltips();
      ChartRedraw(0);
   }

   ENUM_HD_PANEL_ACTION Click(const string object_name)
   {
      if(StringFind(object_name, m_prefix) != 0)
         return HD_ACTION_NONE;

      if(object_name == Name("MINI"))
      {
         ObjectSetInteger(0, object_name, OBJPROP_STATE, false);

         m_collapsed = !m_collapsed;
         m_layout_dirty = true;
         Layout();

         return HD_ACTION_NONE;
      }

      // Hidden controls must not issue a trading action.
      if(m_compact)
         return HD_ACTION_NONE;

      ObjectSetInteger(0, object_name, OBJPROP_STATE, false);
      ChartRedraw(0);

      if(object_name == Name("BUY"))    return HD_ACTION_BUY;
      if(object_name == Name("SELL"))   return HD_ACTION_SELL;
      if(object_name == Name("HEDGE"))  return HD_ACTION_HEDGE;
      if(object_name == Name("CLOSE"))  return HD_ACTION_CLOSE;
      if(object_name == Name("REFILL")) return HD_ACTION_REFILL;
      if(object_name == Name("LOCK"))   return HD_ACTION_LOCK;

      if(object_name == Name("MODE"))      return HD_ACTION_MODE;
      if(object_name == Name("DIRECTION")) return HD_ACTION_DIRECTION;
      if(object_name == Name("BETYPE"))    return HD_ACTION_BE_TYPE;
      if(object_name == Name("HARD"))      return HD_ACTION_HARD;
      if(object_name == Name("BE"))        return HD_ACTION_BE;
      if(object_name == Name("RR"))        return HD_ACTION_RR;
      if(object_name == Name("SESSION"))   return HD_ACTION_SESSION;
      if(object_name == Name("RELOCK"))    return HD_ACTION_RELOCK;

      return HD_ACTION_NONE;
   }
};

#endif