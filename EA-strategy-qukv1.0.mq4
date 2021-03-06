//+------------------------------------------------------------------+
//|                                              autotrading1120.mq4 |
//|                        Copyright 2014, MetaQuotes Software Corp. |
//|                                              http://www.mql5.com |
//+------------------------------------------------------------------+
#include <stderror.mqh>
#include <stdlib.mqh>

#property copyright "Copyright 2014, MetaQuotes Software Corp."
#property link      "http://www.mql5.com"
#property version   "1.0"
#property strict
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+

//model parameter
extern double csl=2.5,ctp=4.5;
extern double decayctp=3.5;
//const int csl=4,ctp=5;
const double cq=2.5;//cn=1.8,cm=1,cq=3
extern double blots = 0.04;

double spread=0.024;
extern int slip=20;
extern int orderLimit=50;
extern int expireSec=900;//20mins
extern int delayTick=10;
extern int tickShort=3;//3
extern int tickMid=80;//80
extern int tickMedian=200;//200
extern int tickLong=1000;//1000
extern int surgeDelayTick=200;
extern int surgerestTick=1000;
//use for record historical bid/ask to compute Ma
double tickbid[1000];
double tickask[1000];
int tickIndex;
bool firstround;//use to donothing in first 1000tick round
double Malongbid,Mamedbid,Mamidbid,Mashortbid;

int onlySell;
int onlyBuy;
double tpprice;
double slprice;
int restTick;
int magicnum;
string sym;

int OnInit()
  {
//--- create timer
   sym = Symbol();
   magicnum =Month()*100+Day();
   firstround=true;
   onlySell=0;
   tickIndex=0;
   onlyBuy=0;
   restTick=0;
   printf("program version quk(20160615)   v1.0.0");
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- destroy timer
   EventKillTimer();
      printf("program will not end ya");
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
   tickbid[tickIndex]=Bid;
   tickask[tickIndex]=Ask;
   if(onlyBuy>0){
      onlyBuy--;
      if(onlyBuy==0){
         restTick=surgerestTick;
         printf("rest");
      }
   }
   if(onlySell>0){
      onlySell--;
      if(onlySell==0){
         restTick=surgerestTick;
         printf("rest");
      }
   }
   checkordertime(Bid,Ask);
   if(!firstround&&restTick==0){
      double sum=0.0;
      double asksum=0.0;
      //compute history tick
      //for efficiency, split for
      for(int i=0;i<tickShort;i++){
         int index=tickIndex+tickLong-i;
         index%=tickLong;
         sum+=tickbid[index];
         asksum+=tickask[index];  
      }
      Mashortbid=sum/tickShort;
      for(int i=tickShort;i<tickMid;i++){
         int index=tickIndex+tickLong-i;
         index%=tickLong;
         sum+=tickbid[index];
         asksum+=tickask[index];    
      }
      Mamidbid=sum/tickMid;
      for(int i=tickMid;i<tickMedian;i++){
         int index=tickIndex+tickLong-i;
         index%=tickLong;
         sum+=tickbid[index]; 
         asksum+=tickask[index];  
      }
      Mamedbid=sum/tickMedian;
      double summed=sum;
      for(int i=tickMedian;i<tickLong;i++){
         int index=tickIndex+tickLong-i;
         index%=tickLong;
         sum+=tickbid[index]; 
         asksum+=tickask[index];  
      }
      Malongbid=(sum-summed)/(tickLong-tickMedian); 
      double avgbid=sum/tickLong;
      double avgask=asksum/tickLong;
      //printf("Malong"+Malongbid+"Mamedid"+Mamedbid+"mid"+Mamidbid+"shot"+Mashortbid);

      spread=avgask-avgbid;
      //order not reach limit, may have some delay 
      if(OrdersTotal()<orderLimit){
         //check condition to OP_buy or sell
         double short_minus_mid_abs=MathAbs(Mashortbid-Mamidbid);
         double spread_multiply_cq=spread*cq;
         int ticket=0;
         //Strategy
         
            //當驟升且回降時，OPEN_SELL，且每次下單後都控制200個TICK內只能以OPENSELL方式進場，當surge結束後1000個TICK不再進場，
            int prevIndexOne = PreviousIndex(tickIndex,1);
            int prevIndexTwo = PreviousIndex(tickIndex,2);
            if((short_minus_mid_abs>spread_multiply_cq)&&(Mashortbid>Mamidbid)&&(tickbid[tickIndex]<tickbid[prevIndexOne])&&(tickbid[prevIndexOne]<tickbid[prevIndexTwo])){ //case1  // 開始回降
               printf("surge-Mid:"+Mamidbid+"short:"+Mashortbid+"NOWbid:"+tickbid[tickIndex]+"NOWask:"+tickask[tickIndex]);
               if(onlyBuy==0){
                  if(onlySell==0){
                     tpprice=Bid-ctp*spread;
                     //slprice=Bid+csl*spread;
                     slprice=Ask+(ctp-csl)*spread;
                     ticket=OrderSend(sym,OP_SELL,blots,Bid,slip,slprice,tpprice,"quickyreverse,surge-BIGSELL",magicnum,0); 
                     onlySell=surgeDelayTick;
                     
                  }else{ //同一個quickie用相同的tp
                     slprice=Ask+(ctp-csl)*spread;
                     ticket=OrderSend(sym,OP_SELL,blots,Bid,slip,slprice,tpprice,"quickyreverse,surge-BIGSELL",magicnum,0);
                     onlySell=surgeDelayTick;
                  }
               }
               restTick=delayTick;
            }
            //當驟降時，OPEN_BUY，且每次下單後都控制200個TICK內只能以OPEN_BUY方式進場，當DROP結束後1000個TICK不再進場，
            else if((short_minus_mid_abs>spread_multiply_cq)&&(Mashortbid<Mamidbid)&&(tickbid[tickIndex]>tickbid[prevIndexOne])&&(tickbid[prevIndexOne]>tickbid[prevIndexTwo])){ //case2  開始回升
               printf("drop-Mid:"+Mamidbid+"short:"+Mashortbid+"NOWbid:"+tickbid[tickIndex]+"NOWask:"+tickask[tickIndex]);
               if(onlySell==0){
                  if(onlyBuy==0){
                     tpprice=Ask+ctp*spread;
                     //slprice=Ask-csl*spread;
                     slprice=Bid-(ctp-csl)*spread;
                     ticket=OrderSend(sym,OP_BUY,blots,Ask,slip,slprice ,tpprice,"quickyreverse,drop-BIGBUY",magicnum,0);
                     onlyBuy=surgeDelayTick;
                  }else{//同一個quickie用相同的tp
                     //slprice=Ask-csl*spread;
                     slprice=Bid-(ctp-csl)*spread;
                     ticket=OrderSend(sym,OP_BUY,blots,Ask,slip,slprice ,tpprice,"quickyreverse,drop-BIGBUY",magicnum,0);
                     onlyBuy=surgeDelayTick;
                  }
               }
               restTick=delayTick;
            }
         if(ticket==-1){
          int check=GetLastError();
          if(check!=ERR_NO_ERROR){
            if(check==141){ //too many request
               //break;
            }
            Print("Ordersend Message not sent. Error: "+check,ErrorDescription(check));
            Print("slprice:"+slprice+" tpprice:"+tpprice);
          }
         }
      }//end ordersend
   }else{
      if(restTick>0){
         restTick--;
      }
   }
   tickIndex++;
   if(tickIndex==1000){
      tickIndex=0;
      firstround=false;
   }
  }
//+------------------------------------------------------------------+
int PreviousIndex(int now,int last){
  int minus = now - last;
  if (minus<0){
    return 1000 + minus;
  }
  return minus;
}
//+------------------------------------------------------------------+
void checkordertime(double bid,double ask){
  double currentTime=TimeCurrent();
  double price;
  int closeCount=10; //one tick only can close 30orders
  int total=OrdersTotal();
  bool decay=false;
  for (int i=0;i<total;i++){
   bool select=OrderSelect(i,SELECT_BY_POS ,MODE_TRADES);
      if(closeCount==0) break;
      if(select&&OrderSymbol()==sym){
         if(OrderOpenTime()+expireSec<currentTime){
         //closeorder 
            //type
            if(OrderType()==OP_BUY){
               price=bid;
            }else{
               price=ask;
            }
            bool close=OrderClose(OrderTicket(), OrderLots(), price, slip,Yellow);
            if(!close){
               int check=GetLastError();
               printf("close error ticket:"+OrderTicket()+"error:"+check);
               if (check != ERR_NO_ERROR) printf("Close not sent. Error: " + ErrorDescription(check) + " Ask:" + Ask);
            }else{
               printf("close by time");
               closeCount--;
               decay=true;
            }
         }
   }//end select
  }//end for
  if(decay){
   ctp=decayctp;
  }
}