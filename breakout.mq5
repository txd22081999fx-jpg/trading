#include <Trade/Trade.mqh>

#define HEARTBEAT_NAME "EA_Alive"

// ===== INPUT =====
input double RiskUSD = 100.0;
input double RR = 2.35;

input int LookbackBars = 30;
input int AvgBodyBars = 5;

input double BodyMultiplierMin = 2;
input double BodyMultiplierMax = 4;

input int ATR_Period = 14;
input double ATR_Multiplier = 2.6;

input int ATR_Avg_Period = 10;
input double ATR_ExpansionFactor = 1.1;

// ===== RSI =====
input int RSI_Period = 14;
input double RSI_Overbought = 70.0;
input double RSI_Oversold = 30.0;

// ===== BE =====
input double BE_Trigger = 0.7;

// ===== Telegram credential =====
input string BotToken = "";
input string ChatID   = "";
input string AccountName = "Unknown";

// ===== GLOBAL =====
int atrHandle;
int rsiHandle;

double atrBuffer[];
double rsiBuffer[];

// ===== SEND TELEGRAM =====
// ===== FORMAT =====
string FormatMsg(string action, string symbol, string side,
                 double volume, double entry, double sl, double tp, string rr)
{
   string msg;
   msg = "=== " + AccountName + " ===\n";
   msg = "=== " + action + " " + side + " " + symbol + " ===\n";
   msg += "Volume: " + DoubleToString(volume, 2) + " lot\n";
   msg += "Entry: " + DoubleToString(entry, _Digits) + "\n";
   msg += "SL: " + DoubleToString(sl, _Digits) + "\n";
   msg += "TP: " + DoubleToString(tp, _Digits) + "\n";
   msg += "RR: " + rr;
   return msg;
}

void SendTelegramMessage(string text)
{
   string url = "https://api.telegram.org/bot" + BotToken + "/sendMessage";

   string headers;
   char post[];
   string data = "chat_id=" + ChatID + "&text=" + AccountName + "\n" + text;
   StringToCharArray(data, post);

   char result[];
   int res = WebRequest("POST", url, "", 5000, post, result, headers);

   if(res == -1)
      Print("Send failed: ", GetLastError());
}

// ===== ATR =====
double GetATR(int shift=1)
{
   if(CopyBuffer(atrHandle, 0, shift, 1, atrBuffer) <= 0)
      return 0;

   return atrBuffer[0];
}

double GetATRAvg()
{
   double sum = 0;

   for(int i=2; i<2+ATR_Avg_Period; i++)
      sum += GetATR(i);

   return sum / ATR_Avg_Period;
}

bool IsTrending()
{
   double atr_now = GetATR(1);
   double atr_avg = GetATRAvg();

   if(atr_avg <= 0)
      return false;

   return (atr_now > atr_avg * ATR_ExpansionFactor);
}

// ===== RSI =====
double GetRSI(int shift=1)
{
   if(CopyBuffer(rsiHandle, 0, shift, 1, rsiBuffer) <= 0)
      return 50.0;

   return rsiBuffer[0];
}

bool IsValidBreakoutRSI()
{
   double rsi = GetRSI(1);

   return (rsi >= RSI_Overbought || rsi <= RSI_Oversold);
}

// ===== LOT =====
double CalculateLot(double entry, double sl_guess)
{
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   double sl_distance = MathAbs(entry - sl_guess);

   double loss_per_lot =
      (sl_distance / tick_size) * tick_value;

   if(loss_per_lot <= 0)
      return 0;

   double lot = RiskUSD / loss_per_lot;

   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   lot = MathRound(lot / step) * step;

   lot = MathMax(minLot,
         MathMin(maxLot, lot));

   return lot;
}

// ===== USD → PRICE =====
double PriceFromUSD(double usd, double lot)
{
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   return (usd / (tick_value * lot)) * tick_size;
}

// ===== BODY =====
double GetBody(int shift)
{
   return MathAbs(
      iClose(_Symbol,_Period,shift)
      -
      iOpen(_Symbol,_Period,shift)
   );
}

double GetAvgBody()
{
   double sum = 0;

   for(int i=2; i<2+AvgBodyBars; i++)
      sum += GetBody(i);

   return sum / AvgBodyBars;
}

// ===== RANGE =====
double GetHighest()
{
   double high = -1e9;

   for(int i=2; i<2+LookbackBars; i++)
      high = MathMax(high,
             iHigh(_Symbol,_Period,i));

   return high;
}

double GetLowest()
{
   double low = 1e9;

   for(int i=2; i<2+LookbackBars; i++)
      low = MathMin(low,
            iLow(_Symbol,_Period,i));

   return low;
}

// ===== BREAK EVEN =====
void ManageBreakEven()
{
   if(!PositionSelect(_Symbol))
      return;

   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl    = PositionGetDouble(POSITION_SL);
   double tp    = PositionGetDouble(POSITION_TP);

   long type = PositionGetInteger(POSITION_TYPE);

   double price =
      (type == POSITION_TYPE_BUY)
      ?
      SymbolInfoDouble(_Symbol, SYMBOL_BID)
      :
      SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double total_dist =
      MathAbs(tp - entry);

   double current_dist =
      MathAbs(price - entry);

   if(total_dist <= 0)
      return;

   // đạt % TP
   if(current_dist >= total_dist * BE_Trigger)
   {
      // đã BE rồi
       if(MathAbs(sl - entry) < _Point * 2)
         return;

      double new_sl = entry;

      // Modify _Symbol, new_sl, tp
   }
}

// ===== ENTRY =====
void CheckEntry()
{
   if(PositionSelect(_Symbol))
      return;

   // ATR expansion
   if(!IsTrending())
      return;

   // RSI breakout filter
   if(!IsValidBreakoutRSI())
      return;

   double close1 = iClose(_Symbol,_Period,1);
   double open1  = iOpen(_Symbol,_Period,1);

   double body1   = GetBody(1);
   double avgBody = GetAvgBody();

   // momentum candle
   if(body1 < avgBody * BodyMultiplierMin || body1 > avgBody * BodyMultiplierMax)
      return;

   double atr = GetATR(1);

   // ===== BUY =====
   if(close1 > GetHighest() && close1 > open1)
   {
      double entry =
         SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double sl_guess =
         entry - atr * ATR_Multiplier;

      double lot =
         CalculateLot(entry, sl_guess);

      if(lot <= 0)
         return;

      double sl_dist =
         PriceFromUSD(RiskUSD, lot);

      double tp_dist =
         PriceFromUSD(RiskUSD * RR, lot);

      double sl = entry - sl_dist;
      double tp = entry + tp_dist;

      // Tính RR thực tế
    double risk      = MathAbs(entry - sl);
    double reward    = MathAbs(tp - entry);
    double rr_actual = DoubleToString(reward / risk, 2);

        // ORDER Buy lot, _Symbol, entry, sl, tp
    string side = "BUY";
    string msg = FormatMsg("BUY", _Symbol, side, lot, entry, sl, tp, rr_actual);
    SendTelegramMessage(msg);
   }

   // ===== SELL =====
   if(close1 < GetLowest() && close1 < open1)
   {
      double entry =
         SymbolInfoDouble(_Symbol, SYMBOL_BID);

      double sl_guess =
         entry + atr * ATR_Multiplier;

      double lot =
         CalculateLot(entry, sl_guess);

      if(lot <= 0)
         return;

      double sl_dist =
         PriceFromUSD(RiskUSD, lot);

      double tp_dist =
         PriceFromUSD(RiskUSD * RR, lot);

      double sl = entry + sl_dist;
      double tp = entry - tp_dist;

     double risk      = MathAbs(entry - sl);
     double reward    = MathAbs(tp - entry);
     double rr_actual = DoubleToString(reward / risk, 2);

        // ORDER Sell lot, _Symbol, entry, sl, tp
    string side = "SELL";
    string msg = FormatMsg("SELL", _Symbol, side, lot, entry, sl, tp, rr_actual);
    SendTelegramMessage(msg);
   }
}

// ===== INIT =====
int OnInit()
{
   EventSetTimer(60); // gọi OnTimer mỗi 60 giây

   // ghi ngay lần đầu
   GlobalVariableSet(HEARTBEAT_NAME, (double)TimeCurrent());
   
   atrHandle =
      iATR(_Symbol,_Period,ATR_Period);

   rsiHandle =
      iRSI(_Symbol,_Period,RSI_Period,PRICE_CLOSE);

   if(atrHandle == INVALID_HANDLE)
      return INIT_FAILED;

   if(rsiHandle == INVALID_HANDLE)
      return INIT_FAILED;

    string msg = FormatMsg("Buy Test", "XAUUSD", "BUY", 0.01, 4000, 3900, 4200, 2);
    SendTelegramMessage(msg);
 

   return INIT_SUCCEEDED;
}

// ===== MAIN =====
void OnTick()
{
   static datetime lastBar = 0;

   datetime currentBar =
      iTime(_Symbol,_Period,1);

   if(currentBar != lastBar)
   {
      lastBar = currentBar;

      CheckEntry();
   }

   ManageBreakEven();
}


void OnTimer()
{
   GlobalVariableSet(HEARTBEAT_NAME, (double)TimeCurrent());
}

void OnDeinit(const int reason)
{
    if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);

   if(rsiHandle != INVALID_HANDLE)
      IndicatorRelease(rsiHandle);
   EventKillTimer();
}