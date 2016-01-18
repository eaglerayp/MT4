//+------------------------------------------------------------------+
//|                                                  EventTrader.mq4 |
//|                                                             Yuan |
//|                                              b98705002@gmail.com |
//+------------------------------------------------------------------+
#property copyright "Yuan"
#property link      "b98705002@gmail.com"
#property version   "1.116"
#property strict
//+------------------------------------------------------------------+
//| Expert initialization function                                   |

#include <stderror.mqh>
#include <stdlib.mqh>

extern int small_slip = 6;
extern int big_slip = 15;
extern double point_value = 0.1;
extern double partial_closerate = 0.25;
extern double half_closerate = 0.5;
extern int simultaneous_symbol = 2;
extern int stp = 800;
extern double risk = 0.1;
extern double prestage_stp = 200;
extern double prestage_risk = 0.02;
extern double announce_stage_stp_perceent = 0.4;

double lots_size; //auto compute
int one_hour;
int magicnum;
//for cmd file input
string filename;
string filter;
//for stage and independent SYM process
string sym;
string event;
string stage;
string strategy;
string winrate_class;
int stage_code;
int stageone_status;

string codeversion;

double total_close_rate;
//for repeat order action
bool offquote_error;
int trade_code;
int close_fail;
string last_sym;
double last_lots;
int last_slip;
string last_comment;
double last_rate;

//for fallback 20%
double fallback_rate[2] = {0.2, 0.5};
int fallback_thresh_pt; //compute fallback threshold
double announce_thres_mul;
bool allowfallbackClose;
int fallback_index;
int ordertype;
double threshold;
double max_profit_value;
double leave_value;

//for stoploss and reverse event
double stoploss_value;
bool reverse_event;
//bool InPreStage;
int stage_reverse_allow_fallback;
int stage_reverse_event_sec;
bool profitcheck;


int OnInit()
{
//---
  lots_size = Lotsize();
  codeversion = "1227:return of reverse stoploss";
  one_hour = 3600; //sec
  stage_reverse_allow_fallback = 0.5 * one_hour;
  stage_reverse_event_sec = 4 * one_hour;
  last_rate = 1;
  fallback_index = 0;
  //change_SL=0;
  filter = "*.txt";
  sym = Symbol();
  filename = sym + ".txt";
  stage_code = 0;
  close_fail = 0;
  stageone_status = 0;
  max_profit_value = 9999;
  leave_value = 9999;
  threshold = 9999;
  ordertype = 0;
  fallback_thresh_pt = 150;
  announce_thres_mul = 1.5;
  total_close_rate = 1;
  reverse_event = false;
  //InPreStage=false;
  profitcheck = false;
  allowfallbackClose = false; //only stage 3 can profit-fallback close
  Print("filepath" + filename);
  //initial delete cmd
  FileDelete(filename);
  Print("version:" + codeversion);
  Print("Symbol=", Symbol());
  Print("Initial size", lots_size);
//---
  return (INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
//---

}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
void OnTick() {
  magicnum = Month() * 100 + Day();
  if ((!offquote_error) && close_fail == 0) { //if no Order error, else repeat order action (open or close)
    if (reverse_event) {
      if (SymOrderTotal() > 0) {
        checkorderfallbackProfit();
        checkordertime();
      } else { //for reach tp case
        reverse_event = false;
        printf("reversed event end");
        //delete existed command
        long search_handle = FileFindFirst(filename, filename);
        if (search_handle != INVALID_HANDLE) { //find
          bool del = FileDelete(filename);
          if (!del) {
            printf("delete file fail");
          }
        }
      }
    } else {
      if (SymOrderTotal() > 0) {
        checkstoploss();
        checkorderfallbackProfit();
        if (profitcheck) {
          checkProfit();
        }
      }
      //recieve command, stage_code=1~5 if get command
      long search_handle = FileFindFirst(filename, filename);
      if (search_handle != INVALID_HANDLE) { //find
        int file_handle = FileOpen(filename, FILE_READ | FILE_TXT);
        if (file_handle != INVALID_HANDLE) { //checkfile
          //  printf("OPEN FILE!");
          event = FileReadString(file_handle);
          stage = FileReadString(file_handle);
          strategy = FileReadString(file_handle);
          winrate_class = FileReadString(file_handle);
          if (StringCompare(stage, "pre") == 0) {
            stage_code = 1;
          } else if (StringCompare(stage, "Act") == 0) {
            stage_code = 2;
          } else if (StringCompare(stage, "Check") == 0) {
            stage_code = 3;
          } else if (StringCompare(stage, "close") == 0) {
            stage_code = 4;
          } else if (StringCompare(stage, "Stage2 close") == 0) { // now using JAVA control close time because we open order at two time, hardly control without timer
            stage_code = 5;
          }
          printf("CMD:" + event + ";" + stage + ";" + strategy + ";" + winrate_class);
          FileClose(file_handle);
          bool del = FileDelete(filename);
          if (!del) {
            printf("delete file fail");
          }
        }

      }

      if (stage_code == 1) { //pre stage
        allowfallbackClose = false;
        lots_size = Lotsize();
        printf("this time lots size:" + lots_size);
        double ask = MarketInfo(sym, MODE_ASK);
        if (StringCompare(strategy, "better") == 0) { //usd forecast>previous USD Strong, Sell EURUSD and set fallback threshold
          string comment = codeversion + stage_code + strategy;
          stageone_status = 1;
          double thres = Bid - fallback_thresh_pt * Point;
          SetThreshold(thres, 2);
          Sell(sym, lots_size, comment, magicnum, small_slip, 1);
          //   InPreStage=true;
        } else if (StringCompare(strategy, "worse") == 0) { //usd forecast<previous USD weak, Buy EURUSD and set fallback threshold
          string comment = codeversion + stage_code + strategy;
          stageone_status = 2;
          double thres = Ask + fallback_thresh_pt * Point;
          SetThreshold(thres, 1);
          Buy(sym, lots_size, comment, magicnum, small_slip, 1);
          //   InPreStage=true;
        }
        stage_code = 0;
      } else if (stage_code == 2) { //announce stage
        //   InPreStage=false;
        profitcheck = false;
        if (StringCompare(strategy, "better") == 0) {
          if (stageone_status == 1) { // better and better  , add!  new 25% fallback baseline
            if (SymOrderTotal() > 0) { //if pre exist thres small
              double thres = Bid - fallback_thresh_pt * Point;
              SetThreshold(thres, 2);
            } else {
              double thres = Bid - announce_thres_mul * fallback_thresh_pt * Point;
              SetThreshold(thres, 2);
            }
            string comment = "big better";
            Sell(sym, Floorsize(lots_size * partial_closerate), comment, magicnum, big_slip, 2); //add
          } else { //WB strategy, close and add right now
            closeAllorder(big_slip, total_close_rate);
            string comment = "announce reverse";
            double thres = Bid - announce_thres_mul * fallback_thresh_pt * Point;
            SetThreshold(thres, 2);
            Sell(sym, lots_size, comment, magicnum, big_slip, 2);
          }
          allowfallbackClose = true;
          stage_code = 0;
        } else if (StringCompare(strategy, "worse") == 0) {
          if (stageone_status == 2) { // worse and worse  , add!  new 25% fallback baseline
            if (SymOrderTotal() > 0) { //if pre exist thres small
              double thres = Ask + fallback_thresh_pt * Point;
              SetThreshold(thres, 1);
            } else {
              double thres = Ask + announce_thres_mul * fallback_thresh_pt * Point;
              SetThreshold(thres, 1);
            }
            string comment = "big worse";
            Buy(sym, Floorsize(lots_size * partial_closerate), comment, magicnum, big_slip, 2); //add
          } else { //BW strategy, close and add right now
            closeAllorder(big_slip, total_close_rate);
            string comment = "announce reverse";
            double thres = Ask + announce_thres_mul * fallback_thresh_pt * Point;
            SetThreshold(thres, 1);
            Buy(sym, lots_size, comment, magicnum, big_slip, 2);
          }
          allowfallbackClose = true;
          stage_code = 0;
        } else { // no action , close right now
          stage_code = 0;
          closeAllorder(small_slip, total_close_rate);
        }
      } else if (stage_code == 3) { //stage 3 set check point allow close, after release 90mins
        allowfallbackClose = true;
        profitcheck = true;
        stage_code = 0;
        printf("fallback max:" + max_profit_value + " leave value:" + leave_value);
      } else if (stage_code == 4) { //stage 4  close partial, before 15 mins
        printf("disallow fallback_close before 15 mins, fallback max:" + max_profit_value + " leave value:" + leave_value);
        stage_code = 0;
        allowfallbackClose = false;
      } else if (stage_code == 5) { //stage 5  close total, close announce stage
        printf("close total");
        stage_code = 0;
        allowfallbackClose = false;
        closeAllorder(small_slip, total_close_rate);
      }
    }
  } else if (close_fail > 0) { // repeat close, close first
    printf("close fail");
    closeAllorder(last_slip, last_rate);
  }
  if (offquote_error) { //off quote error  , repeat last trade
    if (trade_code == 0) { //repeat buy
      offquote_error = false;
      Buy(last_sym, last_lots, last_comment, magicnum, last_slip, 0);
    } else {
      offquote_error = false;
      Sell(last_sym, last_lots, last_comment, magicnum, last_slip, 0);
    }
  }
}
//+------------------------------------------------------------------+
double Lotsize() {
  double balance = AccountInfoDouble(ACCOUNT_BALANCE);
  /*double cost=MarketInfo(Symbol(),MODE_MARGINREQUIRED)/100;
  double risk_limit=cost+stp*point_value;
  double size=floor(freemargin/risk_limit)/100;*/
  double freemargin = balance / simultaneous_symbol;
  double size = Floorsize(freemargin * risk / (stp * point_value * 10)); //max loss (0.1*balance = stp* size)  point*10 because we use 0.00001 as unit
  size = MathMin(size, MarketInfo(Symbol(), MODE_MAXLOT));
  size = MathMax(size, MarketInfo(Symbol(), MODE_MINLOT));
  return size;
}
//+------------------------------------------------------------------+
double Floorsize(double x) {
  double x_mul100 = x * 100;
  double floorx = floor(x_mul100);
  double size = floorx / 100;
  size = MathMin(size, MarketInfo(Symbol(), MODE_MAXLOT));
  size = MathMax(size, MarketInfo(Symbol(), MODE_MINLOT));
  return size;
}
//+------------------------------------------------------------------+
void checkordertime() {
  double currenttime = TimeCurrent();
  int total = OrdersTotal();
  for (int i = 0; i < total; i++) {
    bool select = OrderSelect(i, SELECT_BY_POS , MODE_TRADES);
    if (select) {
      string sym_close = OrderSymbol();
      if (sym_close == sym && OrderOpenTime() + stage_reverse_event_sec < currenttime) { //
        //time up closeAllorder
        printf("close by time; now only stoploss");
        closeAllorder(small_slip, total_close_rate);
      } else if (sym_close == sym && OrderOpenTime() + stage_reverse_allow_fallback < currenttime) {
        allowfallbackClose = true;
      }
    }//end select
  }//end for
}
//+------------------------------------------------------------------+
void checkProfit() {
  int total = OrdersTotal();
  for (int i = 0; i < total; i++) {
    bool select = OrderSelect(i, SELECT_BY_POS , MODE_TRADES);
    if (select) {
      string sym_close = OrderSymbol();
      if (sym_close == sym) {
        if (OrderProfit() < 0) {
          closeAllorder(small_slip, total_close_rate);
          profitcheck = false;
          printf("close by check profit<0");
        }
      }
    }//end select
  }//end for
}
//+------------------------------------------------------------------+
void checkstoploss() {
  int total = OrdersTotal();
  for (int i = 0; i < total; i++) {
    bool select = OrderSelect(i, SELECT_BY_POS , MODE_TRADES);
    if (select) {
      string sym_close = OrderSymbol();
      if (sym_close == sym) {
        if (OrderType() == OP_BUY && Bid < stoploss_value) {
          closeAllorder(big_slip, total_close_rate);
          reverse_event = true;
          Sell(sym, lots_size, "reverse Sell", magicnum, big_slip, 1);
          double thres = Bid - 2 * fallback_thresh_pt * Point;
          SetThreshold(thres, 2);
          printf("close by stoploss, big slip;");
          // InPreStage=false;
        } else if (OrderType() == OP_SELL && Ask > stoploss_value) {
          closeAllorder(big_slip, total_close_rate);
          reverse_event = true;
          Buy(sym, lots_size, "reverse Buy", magicnum, big_slip, 1);
          double thres = Ask + 2 * fallback_thresh_pt * Point;
          SetThreshold(thres, 1);
          printf("close by stoploss, big slip;");
          //  InPreStage=false;
        }

      }
    }//end select
  }//end for
}
//+------------------------------------------------------------------+
int SymOrderTotal() {
  int Symorder = 0;
  int total = OrdersTotal();
  for (int i = 0; i < total; i++) {
    bool select = OrderSelect(i, SELECT_BY_POS , MODE_TRADES);
    if (select) {
      if (sym == OrderSymbol()) {
        Symorder++;
      }
    }//end select
  }//end for
  return Symorder;
}
//+------------------------------------------------------------------+
void SetThreshold(double thresh, int type) { //type1=buy 2=sell
  ordertype = type;
  threshold = thresh;
  printf("new fallback threshold:" + thresh); //20151128
  fallback_index = 0;
  if (type == 1) { //Buy
    max_profit_value = Bid;
    leave_value = 9999;
  } else if (type == 2) { //Sell
    max_profit_value = Ask;
    leave_value = 0;
  }
}
//+------------------------------------------------------------------+
void closeAllorder(int slip, double closerate) {
  printf("in closeAllorder, closerate:" + closerate);
  double price;
  int total = OrdersTotal();
  int sym_orders = 0;
  for (int i = 0; i < total; i++) {
    bool select = OrderSelect(i, SELECT_BY_POS , MODE_TRADES);
    if (select) {
      //closeorder
      string sym_close = OrderSymbol();
      //type
      if (sym_close == sym) {
        sym_orders++;
        if (OrderType() == OP_BUY) {
          price = MarketInfo(sym_close, MODE_BID);
        } else {
          price = MarketInfo(sym_close, MODE_ASK);
        }
        bool close = OrderClose(OrderTicket(), NormalizeDouble(OrderLots() * closerate, 2), price, slip, Yellow);
        if (!close) {
          int check = GetLastError();
          close_fail++;
          last_slip = slip;
          last_rate = closerate;
          printf("close error ticket:" + OrderTicket() + "error:" + check);
          if (check != ERR_NO_ERROR) printf("Close not sent. Error: " + ErrorDescription(check) + " Ask:" + Ask);
        }
      }
    }//end select
  }//end for
   close_fail=SymOrderTotal();
  printf("close end, before close orders:" + sym_orders + " after close:" + SymOrderTotal() + " left, close_fail:" + close_fail);
}
//+------------------------------------------------------------------+
void checkorderfallbackProfit() {
  if (ordertype > 0) {
    if (ordertype == 1) { //buy
      // set max
      if (Bid > max_profit_value) {
        max_profit_value = Bid;
        leave_value = max_profit_value - ((max_profit_value - threshold + fallback_thresh_pt * Point()) * fallback_rate[fallback_index]);
      }
      if (allowfallbackClose && max_profit_value > threshold ) {
        if ( Bid < leave_value) {
          printf("close by fallback:" + fallback_rate[fallback_index] + " Max tick value:" + max_profit_value + " leave value:" + leave_value);
          if (fallback_index == 0) { //close 50%
            leave_value = max_profit_value - ((max_profit_value - threshold + fallback_thresh_pt * Point()) * fallback_rate[++fallback_index]);
            closeAllorder(small_slip, half_closerate);
          } else { //close all and reset parameters
            closeAllorder(small_slip, total_close_rate);
            fallback_index = 0;
            allowfallbackClose = false;
            max_profit_value = 9999;
            leave_value = 9999;
            threshold = 9999;
            ordertype = 0;
          }
        }
      }
    } else { //sell
      // set max
      if (Ask < max_profit_value) {
        max_profit_value = Ask;
        leave_value = max_profit_value + ((threshold + fallback_thresh_pt * Point() - max_profit_value) * fallback_rate[fallback_index]);
      }
      if (allowfallbackClose && max_profit_value < threshold) {
        if (Ask > leave_value) {
          printf("close by fallback" + fallback_rate[fallback_index] + " Max tick value:" + max_profit_value + " leave value:" + leave_value);
          if (fallback_index == 0) { //close 50%
            closeAllorder(small_slip, half_closerate);
            leave_value = max_profit_value + ((threshold + fallback_thresh_pt * Point() - max_profit_value) * fallback_rate[++fallback_index]);
          } else {  //close all and reset parameters
            closeAllorder(small_slip, total_close_rate);
            fallback_index = 0;
            allowfallbackClose = false;
            max_profit_value = 9999;
            leave_value = 9999;
            threshold = 9999;
            ordertype = 0;
          }
        }
      }
    }
  }
}
//+------------------------------------------------------------------+
void Buy(string sym_buy, double lots, string comment, int magic, int slip, int stoploss_stage) {
  double ask = MarketInfo(sym_buy, MODE_ASK);
  double bid = MarketInfo(sym_buy, MODE_BID);
  double point = MarketInfo(sym_buy, MODE_POINT);
  if (stoploss_stage == 1) { // pre stage
    double risk_stp = prestage_risk * AccountInfoDouble(ACCOUNT_BALANCE) / lots;
    risk_stp = (risk_stp > prestage_stp) ? prestage_stp : risk_stp;
    stoploss_value = bid - point * risk_stp; // use bid prevent spread
  } else if (stoploss_stage == 2) { // announce stage
    stoploss_value = bid - point * stp * announce_stage_stp_perceent;
  }
  double sl = bid - stp * point;
  double tp = bid + 1.2 * stp * point;
  int ticket = OrderSend(sym_buy, OP_BUY, lots, ask, slip, sl, tp, comment, magic, 0);
  if (ticket == -1) { // order open error
    int check = GetLastError();
    if (check != ERR_NO_ERROR) {
      printf("BUY error, price:" + ask + " SL:" + sl + " TP:" + tp + " size:" + lots);
      Print("Ordersend Message not sent. Error: " + check, ErrorDescription(check));
      //if(check==136){
      offquote_error = true;
      last_lots = lots;
      last_sym = sym_buy;
      trade_code = 0;
      last_comment = comment;
      last_slip = slip;
      //}
    }
  } else {
    printf("buy trade success, pre_stoploss entry:" + stoploss_value );
  }
}
//+------------------------------------------------------------------+
void Sell(string sym_sell, double lots, string comment, int magic, int slip, int stoploss_stage) {
  double ask = MarketInfo(sym_sell, MODE_ASK);
  double bid = MarketInfo(sym_sell, MODE_BID);
  double point = MarketInfo(sym_sell, MODE_POINT);
  if (stoploss_stage == 1) {  //loss = size *stp
    double risk_stp = prestage_risk * AccountInfoDouble(ACCOUNT_BALANCE) / lots;
    risk_stp = (risk_stp > prestage_stp) ? prestage_stp : risk_stp;
    stoploss_value = ask + point * risk_stp;  // use ask prevent spread
  } else if (stoploss_stage == 2) { // announce stage
    stoploss_value = ask + point * stp * announce_stage_stp_perceent;
  }
  double sl = ask + stp * point;
  double tp = ask - 1.2 * stp * point;
  int ticket = OrderSend(sym_sell, OP_SELL, lots, bid, slip, sl, tp, comment, magic, 0);
  if (ticket == -1) { // order open error
    int check = GetLastError();
    if (check != ERR_NO_ERROR) {
      printf("Sell error, price:" + bid + " SL:" + sl + " TP:" + tp + " size:" + lots);
      Print("Ordersend Message not sent. Error: " + check, ErrorDescription(check));
      //if(check==136){
      offquote_error = true;
      last_lots = lots;
      last_sym = sym_sell;
      trade_code = 1;
      last_comment = comment;
      last_slip = slip;
      //}
    }
  } else {
    printf("sell trade success, pre_stoploss entry:" + stoploss_value);
  }
}