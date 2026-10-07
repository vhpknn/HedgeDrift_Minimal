#ifndef HEDGEDRIFT_ACCOUNTING_ENGINE_MQH
#define HEDGEDRIFT_ACCOUNTING_ENGINE_MQH

#include "Config.mqh"

class CHDAccounting
{
private:
   string m_symbol;
   ulong  m_magic;

   double m_base;
   double m_refill;
   int    m_refill_count;
   double m_realized;
   double m_floating;

   ulong m_processed_deals[];
   ulong m_owned_positions[];

   bool HasDeal(const ulong ticket)
   {
      for(int i = 0; i < ArraySize(m_processed_deals); i++)
      {
         if(m_processed_deals[i] == ticket)
            return true;
      }
      return false;
   }

   bool HasPosition(const ulong identifier)
   {
      for(int i = 0; i < ArraySize(m_owned_positions); i++)
      {
         if(m_owned_positions[i] == identifier)
            return true;
      }
      return false;
   }

   bool RememberDeal(const ulong ticket)
   {
      int size = ArraySize(m_processed_deals);
      if(ArrayResize(m_processed_deals, size + 1) != size + 1)
      {
         Print("[HedgeDrift][ERROR] Cannot store Deal ID.");
         return false;
      }

      m_processed_deals[size] = ticket;
      return true;
   }

   bool RememberPosition(const ulong identifier)
   {
      if(identifier == 0)
         return false;

      if(HasPosition(identifier))
         return true;

      int size = ArraySize(m_owned_positions);
      if(ArrayResize(m_owned_positions, size + 1) != size + 1)
      {
         Print("[HedgeDrift][ERROR] Cannot store Position ID.");
         return false;
      }

      m_owned_positions[size] = identifier;
      return true;
   }

   bool PositionBelongsToEA(const ulong identifier)
   {
      if(HasPosition(identifier))
         return true;

      if(identifier == 0 || !HistorySelectByPosition(identifier))
         return false;

      int total = HistoryDealsTotal();

      for(int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0)
            continue;

         if(HistoryDealGetString(ticket, DEAL_SYMBOL) != m_symbol)
            continue;

         if((ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC) != m_magic)
            continue;

         ENUM_DEAL_ENTRY entry =
            (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);

         if(entry == DEAL_ENTRY_IN)
            return RememberPosition(identifier);
      }

      return false;
   }

public:
   bool Init(const string symbol, const ulong magic,
             const double base_capital)
   {
      m_symbol       = symbol;
      m_magic        = magic;
      m_base         = base_capital;
      m_refill       = 0.0;
      m_refill_count = 0;
      m_realized     = 0.0;
      m_floating     = 0.0;

      ArrayResize(m_processed_deals, 0);
      ArrayResize(m_owned_positions, 0);

      // Existing history is the baseline, not new income.
      if(!HistorySelect(0, TimeCurrent()))
      {
         Print("[HedgeDrift][ERROR] Cannot prepare history baseline.");
         return false;
      }

      int total = HistoryDealsTotal();

      for(int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0)
            continue;

         if(HistoryDealGetString(ticket, DEAL_SYMBOL) != m_symbol)
            continue;

         if(!RememberDeal(ticket))
            return false;
      }

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionGetTicket(i) == 0)
            continue;

         if(PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;

         if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;

         ulong identifier =
            (ulong)PositionGetInteger(POSITION_IDENTIFIER);

         if(!RememberPosition(identifier))
            return false;
      }

      RefreshFloating();
      return true;
   }

   bool ProcessDeal(const ulong ticket)
   {
      if(ticket == 0 || HasDeal(ticket))
         return false;

      if(!HistoryDealSelect(ticket))
      {
         Print("[HedgeDrift][ERROR] Cannot select deal ", ticket);
         return false;
      }

      string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
      if(symbol != m_symbol)
         return false;

      ENUM_DEAL_TYPE type =
         (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);

      if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL)
         return false;

      ulong magic =
         (ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC);

      ulong position_id =
         (ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);

      ENUM_DEAL_ENTRY entry =
         (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);

      double net =
         HistoryDealGetDouble(ticket, DEAL_PROFIT)
         + HistoryDealGetDouble(ticket, DEAL_COMMISSION)
         + HistoryDealGetDouble(ticket, DEAL_SWAP)
         + HistoryDealGetDouble(ticket, DEAL_FEE);

      bool owned = false;

      if(entry == DEAL_ENTRY_IN)
      {
         if(magic == m_magic)
            owned = RememberPosition(position_id);
      }
      else
      {
         // Manual closing deals can have a different Magic.
         owned = PositionBelongsToEA(position_id);
      }

      if(!owned)
         return false;

      if(!RememberDeal(ticket))
         return false;

      m_realized += net;
      RefreshFloating();

      Print("[HedgeDrift][INFO] Deal=", ticket,
            " Net=", DoubleToString(net, 2),
            " EQ=", DoubleToString(Balance(), 2),
            " OR=", DoubleToString(Floating(), 2),
            " TT=", DoubleToString(Equity(), 2));

      return true;
   }

   void RefreshFloating()
   {
      m_floating = 0.0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionGetTicket(i) == 0)
            continue;

         if(PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;

         if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;

         m_floating += PositionGetDouble(POSITION_PROFIT)
                       + PositionGetDouble(POSITION_SWAP);
      }
   }

   int PositionCount()
   {
      int count = 0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionGetTicket(i) == 0)
            continue;

         if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
            (ulong)PositionGetInteger(POSITION_MAGIC) == m_magic)
            count++;
      }

      return count;
   }

   bool Refill(const double amount)
   {
      if(amount <= 0.0)
         return false;

      m_refill += amount;
      m_refill_count++;

      Print("[HedgeDrift][INFO] Refill=", DoubleToString(amount, 2),
            " Count=", m_refill_count,
            " EQ=", DoubleToString(Balance(), 2));

      return true;
   }

   double BaseCapital() { return m_base; }
   double RefillTotal() { return m_refill; }
   int RefillCount() { return m_refill_count; }
   double RealizedNet() { return m_realized; }
   double Balance() { return m_base + m_refill + m_realized; }
   double Floating() { return m_floating; }
   double Equity() { return Balance() + m_floating; }
};

#endif