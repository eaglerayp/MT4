//+------------------------------------------------------------------+
//|                                                  EventTrader.mq4 |
//|                                                             Yuan |
//|                                              b98705002@gmail.com |
//+------------------------------------------------------------------+
#property copyright "Yuan"
#property link      "b98705002@gmail.com"
#property version   "1.00"
#property strict
//+------------------------------------------------------------------+
//| Expert initialization function                                   |

#include <stderror.mqh>
#include <stdlib.mqh>

extern double blots = 1;
extern double super_blots = 1;
extern int slip=5;
extern int outsec=7200;//120mins
extern int sqrt_point_mul=1000;
int magicnum;
string filename;
string result[];
long last_volumes;
long lastM1_volumes;
long volumes;
long max_volumes;
string sym;
string sym2;
string event;
string stage;
string strategy;
int stage_code;
double sqrt_s1;
double sqrt_q1;
string sep;
ushort u_sep; 
string filter;
double basetime;
bool offquote_error;
int trade_code;
string last_sym;
double last_lots;
string last_comment;
string sym3;
int OnInit()
  {
//---
   filter="*.txt";
   filename="cmd.txt";
   stage_code=0;
   max_volumes=0;
   last_volumes=0;
   lastM1_volumes=0;
   volumes=0;
   sep=";";                // A separator as a character
   u_sep=StringGetCharacter(sep,0);                 // The code of the separator character
   printf("program version EventTrader0324");
   sym3="USDNOK";
//---
   return(INIT_SUCCEEDED);
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
void OnTick(){
   magicnum =Month()*100+Day();
   if(!offquote_error){
      if(OrdersTotal()>0){
         checkordertime();
         checkorderbyVolume();
      }
      long search_handle=FileFindFirst(filter,filename);
      if(search_handle!=INVALID_HANDLE){//find
         int file_handle=FileOpen(filename,FILE_READ|FILE_TXT);
         if(file_handle!=INVALID_HANDLE){  //checkfile
             printf("OPEN FILE!");
             sym=FileReadString(file_handle);
             int k=StringSplit(sym,u_sep,result);
             if(k>1){
               sym=result[0];
               sym2=result[1];
             }
             event=FileReadString(file_handle);
             stage=FileReadString(file_handle);
             strategy=FileReadString(file_handle);
             if(StringCompare(stage,"pre")==0){
               stage_code=1;
               double ask=MarketInfo(sym,MODE_ASK);
               double point=MarketInfo(sym,MODE_POINT);
               double sqrt_ask_diff=sqrt(ask)*sqrt_point_mul*point;
               sqrt_s1= ask-sqrt_ask_diff;
               sqrt_q1= ask+sqrt_ask_diff;
               if(StringCompare(strategy,"market")==0){
                  printf("looking market");
                  basetime=TimeCurrent();
               }
             }else if(StringCompare(stage,"Act")==0){
               stage_code=2;
             }
             printf("CMD:"+sym+";"+event+";"+stage+";"+strategy);
             FileClose(file_handle);
             bool del=FileDelete(filename);
             if(!del){
               printf("delete file fail");
             }
          }
   
       }
     
       if(stage_code==1){  //pre stage
         int ticket=0;
         double ask=MarketInfo(sym,MODE_ASK);
         if(StringCompare(strategy,"better")==0){// BUY GBP
            string comment=stage_code+strategy;
            Buy(sym2,blots,comment,magicnum);
         }else if(StringCompare(strategy,"worse")==0){
            string comment=stage_code+strategy;
            Sell(sym,blots,comment,magicnum);
         }else{  //look market strategy
            if(TimeCurrent()-basetime>outsec){
               printf("after 2 hour, no looking market");
               stage_code=0;
            }
            if(ask>sqrt_q1){        //多GBP
               string comment=stage_code+strategy;
               Buy(sym2,blots,comment,magicnum);
            }else if(ask<sqrt_s1){  //空EUR
               string comment=stage_code+strategy;
               Sell(sym,blots,comment,magicnum);
            }
         }
       }else if(stage_code==2){//after parse actual
          double ask=MarketInfo(sym,MODE_ASK);
          double bid=MarketInfo(sym,MODE_BID);
          double point=MarketInfo(sym,MODE_POINT);
          int ticket=0;
          if(StringCompare(strategy,"better")==0){  //USD strong   sell EUR GBP
            string comment=stage_code+strategy;
            Sell(sym2,super_blots,comment,magicnum);
            Sell(sym,super_blots,comment,magicnum);
            Buy(sym3,super_blots,comment,magicnum);
          }else if(StringCompare(strategy,"worse")==0){   // USD worse   BUY EUR GBP
            string comment=stage_code+strategy;
            Buy(sym2,super_blots,comment,magicnum);
            Buy(sym,super_blots,comment,magicnum);
            Sell(sym3,super_blots,comment,magicnum);
          }else{ // no action
            stage_code=0;
          }
       }
    }else{  //off quote error  , repeat last trade
      if(trade_code==0){ //repeat buy
         offquote_error=false;
         Buy(last_sym,last_lots,last_comment,magicnum);
      }else{
         offquote_error=false;
         Sell(last_sym,last_lots,last_comment,magicnum);
      }
    }
  }
//+------------------------------------------------------------------+
void checkordertime(){
  double currenttime=TimeCurrent();
  double price;
  int total=OrdersTotal();
  for (int i=0;i<total;i++){
   bool select=OrderSelect(i,SELECT_BY_POS ,MODE_TRADES);
      if(select){
          if(OrderOpenTime()+outsec<currenttime){   //120分以上的單關掉
         //closeorder 
            string sym_close=OrderSymbol();
            //type
            if(OrderType()==OP_BUY){
               price=MarketInfo(sym_close,MODE_BID);
            }else{
               price=MarketInfo(sym_close,MODE_ASK);
            }
            bool close=OrderClose(OrderTicket(),OrderLots(), price, slip,Yellow);
            if(!close){
               int check=GetLastError();
               printf("close error ticket:"+OrderTicket()+"error:"+check);
               if(check!=ERR_NO_ERROR) Print("Message not sent. Error: ",ErrorDescription(check));
            }else{
               printf("close by time 120mins");
            }
         }
   }//end select
  }//end for
}
//+------------------------------------------------------------------+
void checkorderbyVolume(){
  double price;
  //成交量滑落就全close
  last_volumes=volumes;
  volumes=iVolume(sym,PERIOD_M5,0);
  long leave_limit=max_volumes/3;
  if(volumes<last_volumes){//M1 stage 一個volume循環結束
  lastM1_volumes=last_volumes;
   if(lastM1_volumes>max_volumes){
      max_volumes=last_volumes;
   }else if(lastM1_volumes<=leave_limit){//close orders
        int total=OrdersTotal();
        for (int i=0;i<total;i++){
         bool select=OrderSelect(i,SELECT_BY_POS ,MODE_TRADES);
            if(select){
               //closeorder 
                  string sym_close=OrderSymbol();
                  //type
                  if(OrderType()==OP_BUY){
                     price=MarketInfo(sym_close,MODE_BID);
                  }else{
                     price=MarketInfo(sym_close,MODE_ASK);
                  }
                  bool close=OrderClose(OrderTicket(),OrderLots(), price, slip,Yellow);
                  if(!close){
                     int check=GetLastError();
                     printf("close error ticket:"+OrderTicket()+"error:"+check);
                     if(check!=ERR_NO_ERROR) Print("Message not sent. Error: ",ErrorDescription(check));
                  }else{
                     printf("close by volume, max volume:"+max_volumes+"last tick volumes:"+lastM1_volumes);
                     max_volumes=0;
                     last_volumes=0;
                     lastM1_volumes=0;
                     volumes=0;
                  }
         }//end select
        }//end for

   }
  }
}
//+------------------------------------------------------------------+
void Buy(string sym_buy,double lots,string comment,int magic){
   double ask=MarketInfo(sym_buy,MODE_ASK);
   double bid=MarketInfo(sym_buy,MODE_BID);
   double point=MarketInfo(sym_buy,MODE_POINT);
   double sqrt_ask_diff=sqrt(ask)*sqrt_point_mul*point;
   double sl= bid-3*sqrt_ask_diff;
   double tp= ask+sqrt_ask_diff;
   int ticket=OrderSend(sym_buy,OP_BUY,lots,ask,slip,sl,tp,comment,magic,0);
   if(ticket==-1){// order open error
       int check=GetLastError();
       if(check!=ERR_NO_ERROR){
         printf("BUY error, price:"+ask+" SL:"+sl+" TP:"+tp);
         Print("Ordersend Message not sent. Error: "+check,ErrorDescription(check));
         if(check==136){
            offquote_error=true;
            last_lots=lots;
            last_sym=sym_buy;
            trade_code=0;
            last_comment=comment;
         }
       }
   }else{
      stage_code=0;
   }
}
//+------------------------------------------------------------------+
void Sell(string sym_sell,double lots,string comment,int magic){
   double ask=MarketInfo(sym_sell,MODE_ASK);
   double bid=MarketInfo(sym_sell,MODE_BID);
   double point=MarketInfo(sym_sell,MODE_POINT);
   double sqrt_ask_diff=sqrt(ask)*sqrt_point_mul*point;
   double sl=ask+3*sqrt_ask_diff;
   double tp=bid-sqrt_ask_diff;
   int ticket=OrderSend(sym_sell,OP_SELL,lots,bid,slip,sl,tp,comment,magic,0);
   if(ticket==-1){// order open error
       int check=GetLastError();
       if(check!=ERR_NO_ERROR){
         printf("Sell error, price:"+bid+" SL:"+sl+" TP:"+tp);
         Print("Ordersend Message not sent. Error: "+check,ErrorDescription(check));
         if(check==136){
            offquote_error=true;
            last_lots=lots;
            last_sym=sym_sell;
            trade_code=1;
            last_comment=comment;
         }
       }
   }else{
      stage_code=0;
   }
}