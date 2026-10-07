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
   HD_ACTION_LOCK
};

class CHDPanel
{
private:
   string m_prefix;

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
      ObjectSetString(0, Name(suffix), OBJPROP_TEXT, value);
   }

public:
   bool Create()
   {
      m_prefix = "HD_" + IntegerToString((long)InpMagicNumber) + "_";
      Destroy();

      string background = Name("BG");

      if(!ObjectCreate(0, background, OBJ_RECTANGLE_LABEL, 0, 0, 0))
         return false;

      Common(background, 10, 20);
      ObjectSetInteger(0, background, OBJPROP_XSIZE, 420);
      ObjectSetInteger(0, background, OBJPROP_YSIZE, 300);
      ObjectSetInteger(0, background, OBJPROP_BGCOLOR, C'24,24,37');
      ObjectSetInteger(0, background, OBJPROP_COLOR, C'69,71,90');
      ObjectSetInteger(0, background, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, background, OBJPROP_ZORDER, 0);

      bool ok = true;

      if(!Label("HEADER", 24, 32, C'249,226,175', 11)) ok = false;
      if(!Label("STATE", 24, 60, C'205,214,244', 10)) ok = false;
      if(!Label("CAP", 24, 86, C'205,214,244', 10)) ok = false;
      if(!Label("METRICS", 24, 112, C'137,180,250', 10)) ok = false;
      if(!Label("LOCKVALUE", 24, 138, C'205,214,244', 10)) ok = false;
      if(!Label("WARNING", 24, 164, C'243,139,168', 9)) ok = false;

      if(!Button("BUY", "BUY", 24, 192,
                 C'30,102,245', clrWhite)) ok = false;

      if(!Button("SELL", "SELL", 162, 192,
                 C'230,69,83', clrWhite)) ok = false;

      if(!Button("HEDGE", "HEDGE OPEN", 300, 192,
                 C'136,57,239', clrWhite)) ok = false;

      if(!Button("LOCK", "LOCK PRICE", 24, 236,
                 C'49,50,68', C'205,214,244')) ok = false;

      if(!Button("REFILL", "REFILL", 162, 236,
                 C'49,50,68', C'205,214,244')) ok = false;

      if(!Button("CLOSE", "CLOSE ALL", 300, 236,
                 C'229,200,144', C'17,17,27')) ok = false;

      Text("WARNING", "PHASE 2: FIXED LOT | NO SL / BE / RR");

      if(!ok)
         Destroy();

      ChartRedraw(0);
      return ok;
   }

   void Destroy()
   {
      if(StringLen(m_prefix) > 0)
         ObjectsDeleteAll(0, m_prefix);

      ChartRedraw(0);
   }

   void Update(CHDAccounting &accounting)
   {
      Text("HEADER",
           "HedgeDrift " + string(HD_VERSION) + " | "
           + _Symbol + " | #" + IntegerToString((long)InpMagicNumber));

      Text("STATE",
           "Manual controls | Cycle: " + HD_CycleName(g_hd.cycle)
           + " | Pos: " + IntegerToString(accounting.PositionCount()));

      Text("CAP",
           "Cap: " + DoubleToString(accounting.BaseCapital(), 2)
           + " | Ref: " + DoubleToString(accounting.RefillTotal(), 2)
           + " (" + IntegerToString(accounting.RefillCount()) + ")"
           + " | Lot: " + DoubleToString(InpStartLot, 4));

      Text("METRICS",
           "EQ: " + DoubleToString(accounting.Balance(), 2)
           + " | OR: " + DoubleToString(accounting.Floating(), 2)
           + " | TT: " + DoubleToString(accounting.Equity(), 2));

      Text("LOCKVALUE",
           "Lock Price: "
           + (g_hd.lock_price > 0.0
              ? DoubleToString(g_hd.lock_price, _Digits)
              : "Not set"));

      Text("REFILL", "REFILL " + DoubleToString(InpRefillAmount, 2));

      ChartRedraw(0);
   }

   ENUM_HD_PANEL_ACTION Click(const string object_name)
   {
      if(StringFind(object_name, m_prefix) != 0)
         return HD_ACTION_NONE;

      ObjectSetInteger(0, object_name, OBJPROP_STATE, false);
      ChartRedraw(0);

      if(object_name == Name("BUY"))    return HD_ACTION_BUY;
      if(object_name == Name("SELL"))   return HD_ACTION_SELL;
      if(object_name == Name("HEDGE"))  return HD_ACTION_HEDGE;
      if(object_name == Name("CLOSE"))  return HD_ACTION_CLOSE;
      if(object_name == Name("REFILL")) return HD_ACTION_REFILL;
      if(object_name == Name("LOCK"))   return HD_ACTION_LOCK;

      return HD_ACTION_NONE;
   }
};

#endif