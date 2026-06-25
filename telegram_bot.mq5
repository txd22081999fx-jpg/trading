input string BotToken = "";
input string ChatID   = "";
input string AccountName = "";

// ===== CACHE =====
double lastSL = 0;
double lastTP = 0;
double lastVolume = 0;
string lastSymbol = "";

// ===== TELEGRAM =====
long lastUpdateID = 0;

// ===== SEND TELEGRAM =====
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

// ===== RR =====
string GetRR(double entry, double sl, double tp, bool isBuy)
{
   if(sl == 0 || tp == 0) return "N/A";

   double risk   = isBuy ? entry - sl : sl - entry;
   double reward = isBuy ? tp - entry : entry - tp;

   if(risk <= 0 || reward <= 0) return "N/A";

   return "1:" + DoubleToString(reward / risk, 2);
}

// ===== FORMAT =====
string FormatMsg(string action, string symbol, string side,
                 double volume, double sl, double tp, string rr)
{
   string msg;
   msg = "=== " + AccountName + " ===\n";
   msg = "=== " + action + " " + side + " " + symbol + " ===\n";
   msg += "Volume: " + DoubleToString(volume, 2) + " lot\n";
   msg += "SL: " + DoubleToString(sl, _Digits) + "\n";
   msg += "TP: " + DoubleToString(tp, _Digits) + "\n";
   msg += "RR: " + rr;
   return msg;
}

// ===== HANDLE COMMAND =====
void HandleCommand(string cmd)
{
   StringTrimLeft(cmd);
   StringTrimRight(cmd);

   if(cmd == "running?" || cmd == "/running")
   {
      SendTelegramMessage("yes");
      return;
   }

   if(cmd == "status")
   {
      if(PositionSelect(_Symbol))
         SendTelegramMessage("Bot is trading");
      else
         SendTelegramMessage("No active trade");
      return;
   }

   if(cmd == "balance")
   {
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      SendTelegramMessage("Balance: " + DoubleToString(bal,2));
      return;
   }

   if(cmd == "equity")
   {
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      SendTelegramMessage("Equity: " + DoubleToString(eq,2));
      return;
   }
   
   if(cmd == "alive")
   {
      string msg;
      double alive = GlobalVariableGet("EA_Alive");
   
      msg += TimeToString((datetime)alive, TIME_SECONDS);
      SendTelegramMessage(msg);
      return;
   }
   
   if(cmd == "inputs")
   {
      string msg;
   
      msg  = "===== EA INPUTS =====\n";
   
      msg += "RiskUSD: "
             + DoubleToString(
                  GlobalVariableGet("EA_RiskUSD"), 2
               ) + "\n";
   
      msg += "RR: "
             + DoubleToString(
                  GlobalVariableGet("EA_RR"), 2
               ) + "\n";
   
      msg += "LookbackBars: "
             + IntegerToString(
                  (int)GlobalVariableGet("EA_LookbackBars")
               ) + "\n";
   
      msg += "AvgBodyBars: "
             + IntegerToString(
                  (int)GlobalVariableGet("EA_AvgBodyBars")
               ) + "\n";
   
      msg += "BodyMultiplier: "
             + DoubleToString(
                  GlobalVariableGet("EA_BodyMultiplier"), 2
               ) + "\n";
   
      msg += "ATR_Multiplier: "
             + DoubleToString(
                  GlobalVariableGet("EA_ATR_Multiplier"), 2
               ) + "\n";
   
      msg += "ATR_Avg_Period: "
             + IntegerToString(
                  (int)GlobalVariableGet("EA_ATR_Avg_Period")
               ) + "\n";
   
      msg += "RSI_Overbought: "
             + DoubleToString(
                  GlobalVariableGet("EA_RSI_Overbought"), 2
               ) + "\n";
   
      msg += "RSI_Oversold: "
             + DoubleToString(
                  GlobalVariableGet("EA_RSI_Oversold"), 2
               ) + "\n";
   
      msg += "BE_Trigger: "
             + DoubleToString(
                  GlobalVariableGet("EA_BE_Trigger"), 2
               );
   
      SendTelegramMessage(msg);
   
      return;
   }
}

// ===== GET TELEGRAM COMMAND =====
void CheckTelegramCommand()
{
   string url = "https://api.telegram.org/bot" + BotToken +
                "/getUpdates?offset=" + (string)(lastUpdateID + 1);

   char result[];
   string headers;
   char post[];

   int res = WebRequest("GET", url, "", 5000, post, result, headers);

   if(res == -1)
   {
      Print("GetUpdates failed: ", GetLastError());
      return;
   }

   string json = CharArrayToString(result);

   int pos = 0;

   // ===== LOOP ALL UPDATES =====
   while(true)
   {
      int posUpdate = StringFind(json, "\"update_id\":", pos);
      if(posUpdate == -1) break;

      int startID = posUpdate + 12;
      int endID   = StringFind(json, ",", startID);

      long updateID = (long)StringToInteger(
         StringSubstr(json, startID, endID - startID)
      );

      // tìm text trong cùng block
      int posText = StringFind(json, "\"text\":\"", posUpdate);

      if(posText != -1)
      {
         int startText = posText + 8;
         int endText   = StringFind(json, "\"", startText);

         string text = StringSubstr(json, startText, endText - startText);

         HandleCommand(text);
      }

      // update ID sau khi xử lý
      lastUpdateID = updateID;

      pos = endID;
   }
}

// ===== CHECK MODIFY =====
void CheckModify(string symbol)
{
   if(!PositionSelect(symbol)) return;

   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);
   double volume = PositionGetDouble(POSITION_VOLUME);
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   long type = PositionGetInteger(POSITION_TYPE);

   string side = (type == POSITION_TYPE_BUY) ? "BUY" : "SELL";

   if(symbol == lastSymbol &&
      sl == lastSL &&
      tp == lastTP &&
      volume == lastVolume)
      return;

   if(lastSymbol == symbol)
   {
      string rr = GetRR(entry, sl, tp, side == "BUY");
      string msg = FormatMsg("MODIFY", symbol, side, volume, sl, tp, rr);
      SendTelegramMessage(msg);
   }

   lastSL = sl;
   lastTP = tp;
   lastVolume = volume;
   lastSymbol = symbol;
}

// ===== TRADE EVENT =====
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      ulong deal = trans.deal;

      if(HistoryDealSelect(deal))
      {
         string symbol = HistoryDealGetString(deal, DEAL_SYMBOL);
         double volume = HistoryDealGetDouble(deal, DEAL_VOLUME);
         int type      = (int)HistoryDealGetInteger(deal, DEAL_TYPE);
         int entry     = (int)HistoryDealGetInteger(deal, DEAL_ENTRY);

         string side = (type == DEAL_TYPE_BUY) ? "BUY" : "SELL";

         // ===== OPEN =====
         if(entry == DEAL_ENTRY_IN)
         {
            if(PositionSelect(symbol))
            {
               double sl = PositionGetDouble(POSITION_SL);
               double tp = PositionGetDouble(POSITION_TP);
               double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);

               string rr = GetRR(entryPrice, sl, tp, side == "BUY");

               string msg = FormatMsg("OPEN", symbol, side, volume, sl, tp, rr);
               SendTelegramMessage(msg);

               lastSymbol = symbol;
               lastSL = sl;
               lastTP = tp;
               lastVolume = volume;
            }
         }

         // ===== CLOSE =====
         if(entry == DEAL_ENTRY_OUT)
         {
            string msg = FormatMsg(
                           "CLOSE",
                           symbol,
                           (side == "BUY") ? "SELL" : "BUY",
                           volume,
                           0,
                           0,
                           "N/A"
                        );
            SendTelegramMessage(msg);

            lastSymbol = "";
         }
      }
   }

   if(trans.symbol != "")
   {
      CheckModify(trans.symbol);
   }
}

// ===== TIMER CHECK TELEGRAM =====
void OnTick()
{
   static datetime lastCheck = 0;

   if(TimeCurrent() - lastCheck >= 3)
   {
      CheckTelegramCommand();
      lastCheck = TimeCurrent();
   }
}

