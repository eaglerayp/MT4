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
int lots_size[3]={6,3,1};
string sym;
string event;
string stage;
string strategy;
int stage_code;
double stdev_s1[3];
double stdev_q1[3];
string sep;
ushort u_sep; 
string filter;
double basetime;
bool offquote_error;
int trade_code;
int close_fail;
string last_sym;
double last_lots;
string last_comment;
int limit_index;
int OnInit()
  {
//---
   limit_index=0;
   filter="*.txt";
   filename="cmd.txt";
   stage_code=0;
   close_fail=0;
   sep=";";                // A separator as a character
   u_sep=StringGetCharacter(sep,0);                 // The code of the separator character
   printf("program version EventTrader0330");
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
   if(!offquote_error&&close_fail==0){
      long search_handle=FileFindFirst(filter,filename);
      if(search_handle!=INVALID_HANDLE){//find
         int file_handle=FileOpen(filename,FILE_READ|FILE_TXT);
         if(file_handle!=INVALID_HANDLE){  //checkfile
             printf("OPEN FILE!");
             sym=FileReadString(file_handle);
             int k=StringSplit(sym,u_sep,result);
             if(k>1){
               sym=result[0];
             }
             event=FileReadString(file_handle);
             stage=FileReadString(file_handle);
             strategy=FileReadString(file_handle);
             string stdev_input=FileReadString(file_handle);
             if(StringCompare(stage,"pre")==0){
               stage_code=1;
               double ask=MarketInfo(sym,MODE_ASK);
               double point=MarketInfo(sym,MODE_POINT);
               double stdev=StrToDouble(stdev_input);
               double half_stdev=0.5*stdev;
               stdev_s1[0]= ask-stdev;
               stdev_q1[0]= ask+stdev;
               stdev_s1[1]= stdev_s1[0]-half_stdev;
               stdev_q1[1]= stdev_q1[0]+half_stdev;
               stdev_s1[2]= stdev_s1[1]-half_stdev;
               stdev_q1[2]= stdev_q1[1]+half_stdev;
               limit_index=0;
               printf("looking market, s1:"+stdev_s1[0]+"q1:"+stdev_q1[0]);
             }else if(StringCompare(stage,"End")==0){
               stage_code=3;
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
          //look market strategy
         if(ask>stdev_q1[limit_index]){        //BUY EUR
            string comment=stage_code+strategy;
            Buy(sym,lots_size[limit_index++],comment,magicnum);
         }else if(ask<stdev_s1[limit_index]){  //SELL EUR
            string comment=stage_code+strategy;
            Sell(sym,lots_size[limit_index++],comment,magicnum);
         }
       }else if(stage_code==3){//close order
         closeAllorder();
         stage_code=0;
       }
    }else if(close_fail>0){ // repeat close
      if(OrdersTotal()==0){
         close_fail=0;
      }else{
         closeAllorder();
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
void closeAllorder(){
  double currenttime=TimeCurrent();
  double price;
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
               close_fail++;
               printf("close error ticket:"+OrderTicket()+"error:"+check);
               if(check!=ERR_NO_ERROR) Print("Message not sent. Error: ",ErrorDescription(check));
            }
   }//end select
  }//end for
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
   }
}