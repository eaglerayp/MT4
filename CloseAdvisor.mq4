//+------------------------------------------------------------------+
//|                                                 CloseAdvisor.mq4 |
//|                                                             Yuan |
//|                                              b98705002@gmail.com |
//+------------------------------------------------------------------+
#property copyright "Yuan"
#property link      "b98705002@gmail.com"
#property version   "1.00"
#property strict
#include <stderror.mqh>
#include <stdlib.mqh>

extern double holdTime = 1800;  //sec
extern int defaultSlip = 5;
extern double fallbackRate = 0.5;
const double totalCloseRate = 1.0;

// assume maximum concurreny trade is 256
const int maxConcurrentTrade = 256;
const int lengthForHash = 255;
const double ten = 10;
const double zero = 0.0;
const double one = 1.0;

// for tracking collision
bool collision = false;
// bool tracked[256];
int trackedTicket[256];
double maxProfitTracker[256];
double maxLossTracker[256];
double threshold[256];
double stopLoss[256];
// double takeProfit[256];
double leftRate;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
//---
//---
	leftRate = one - fallbackRate;
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
void OnTick()
{

	// Main close condition:
	// 1. Time
	// 2. Stoploss
	// 3. Profit fallback
	checkOrders();
	// Log message onStart
	// 1. max loss
	// 2. max profit
	// 3. max profit during the trade
}
//+------------------------------------------------------------------+
double getOnePercent() {
	// 1% = lot size * 1 lot cost * 0.01
	// this 1 percent calculate the how much lost means 1 percent of the trade (by the lot size).
	// double marginCost = double(MarketInfo(OrderSymbol(), MODE_MARGINREQUIRED));
	// double onePercent = OrderLots() * marginCost * 0.01;
	// return onePercent;

	double balance = AccountInfoDouble(ACCOUNT_BALANCE);
	double onePercent = balance * 0.01;
	return onePercent;
}
//+------------------------------------------------------------------+
double getTenPercent() {
	double balance = AccountInfoDouble(ACCOUNT_BALANCE);
	double onePercent = balance * 0.1;
	return onePercent;
}


//+------------------------------------------------------------------+
int hashIndex(int ticket) {
	int index = ticket & lengthForHash;

	// check first tracked this order?
	if (trackedTicket[index] == ticket){
		// common case done
		return index;
	}
	if (trackedTicket[index] == 0){
		// maybe one of collision trade closed, so iterate trackedTicket to check if collisions finish
		if (!collision){
			// first
			InitTradeLogInfo(ticket,index);
		}
		int checkIndex = findTrackedTicket(ticket);
		if (checkIndex<maxConcurrentTrade){
			// still in collision period
			return checkIndex;
			collision = false;
		}
		// end of collision period
		InitTradeLogInfo(ticket,index);
		return index;
	}
	if (trackedTicket[index] != ticket){
		// collision case
		printf("ticket :" + ticket + ", had collision!");
		while (true){
			if (trackedTicket[index]==0){
				// first collision
				collision = true;
				InitTradeLogInfo(ticket,index);
				return index;
			} 
			if (trackedTicket[index]==ticket){
				// in collision period
				return index;
			}
			index++;
		}
		return index;
	}
	return index;
}
//+------------------------------------------------------------------+
int findTrackedTicket(int ticket){
	for (int i = 0; i < maxConcurrentTrade; i++) {
		if (trackedTicket[i] == ticket){
			return i;
		}
	}
	return 1024;
}
//+------------------------------------------------------------------+
// checkOrders iterate all orders and check time, profit and fallback respectively.
//+------------------------------------------------------------------+
void checkOrders() {
	int total = OrdersTotal();
	for (int i = 0; i < total; i++) {
		bool select = OrderSelect(i, SELECT_BY_POS , MODE_TRADES);
		if (select) {
			// check profit
			int ticket = OrderTicket();
			int index = hashIndex(ticket);
			checkProfit(ticket, index);
			// check fallback
			// check time
			checkTime(ticket, index);
		}//end select
	}//end for
}
//+------------------------------------------------------------------+
// void resetTracked() {
// 	for (int i = 0; i < maxConcurrentTrade; i++) {
// 		tracked[i]=false;
// 	}
// }
//+------------------------------------------------------------------+
void InitTradeLogInfo(int ticket, int index) {
	printf("ticket :" + ticket + ", first tracked at index:" + index);
	double onePercent = getOnePercent();
	printf("lot size :" + OrderLots() + ", one percent treshold:" + onePercent);
	trackedTicket[index] = ticket;
	threshold[index] = 3 * onePercent;
	double tenPercent = getTenPercent();
	stopLoss[index] = -tenPercent;
	// takeProfit[index] = tenPercent;
}
//+------------------------------------------------------------------+
void checkTime(int ticket, int index) {
	double currentTimestemp = TimeCurrent();
	double openTimestamp = OrderOpenTime();
	double leaveTimestamp = openTimestamp + holdTime;

	if ( leaveTimestamp < currentTimestemp) { //
		//time up CloseAllOrder
		printf("ticket:" + ticket + ", close by time");
		CloseOrder(ticket, index, defaultSlip, totalCloseRate);
	}
}
//+------------------------------------------------------------------+
void checkProfit(int ticket, int index) {
	double profit = OrderProfit();

	// update max profit
	if (profit > maxProfitTracker[index]) {
		maxProfitTracker[index] = profit;
		return;
	}
	// update max Loss
	if (profit < maxLossTracker[index]) {
		maxLossTracker[index] = profit;
	}

	// check fallback
	double onePercentThreshold = threshold[index];
	if (maxProfitTracker[index] > onePercentThreshold && profit < maxProfitTracker[index] * leftRate) {
		printf("ticket:" + ticket + ", close by fallback profit:" + profit);
		CloseOrder(ticket, index, defaultSlip, totalCloseRate);
		return;
	}

	// hard stoploss
	if (profit < stopLoss[index]) {
		printf("ticket:" + ticket + ", close by stoploss profit:" + profit);
		CloseOrder(ticket, index, defaultSlip, totalCloseRate);
	}
}
//+------------------------------------------------------------------+
void CloseOrder(int ticket, int index, int slip, double closerate) {
	printf("Start closing Order:" + ticket + ", closerate:" + closerate);
	double price;

	bool select = OrderSelect(ticket, SELECT_BY_TICKET  , MODE_TRADES);
	if (select) {
		//closeorder
		if (OrderType() == OP_BUY) {
			price = MarketInfo(OrderSymbol(), MODE_BID);
		} else {
			price = MarketInfo(OrderSymbol(), MODE_ASK);
		}
		bool close = OrderClose(ticket, NormalizeDouble(OrderLots() * closerate, 2), price, slip, Yellow);
		if (!close) {
			int check = GetLastError();
			// last_slip = slip;
			// last_rate = closerate;
			if (check != ERR_NO_ERROR) {
				printf("Close not sent. Error: " + ErrorDescription(check) + " price:" + price);
				return;
			}
			printf("close error ticket:" + ticket + "error:" + check);
			return;
		}
	}//end select

	// Close succesfully
	// Log message during the trade:
	// 1. max loss
	// 3. max profit
	printf("ticket:" + ticket + ", close end");
	printf("max profit:" + maxProfitTracker[index]);
	printf("max loss:" + maxLossTracker[index]);
	maxProfitTracker[index] = zero;
	maxLossTracker[index] = zero;
	threshold[index] = zero;
	trackedTicket[index] = zero;
}

//+------------------------------------------------------------------+
// double Lotsize() {
// 	double equity = AccountInfoDouble(ACCOUNT_EQUITY);
// 	double cost = MarketInfo(Symbol(), MODE_MARGINREQUIRED);
// 	double perEquity = equity / (simultaneous_symbol);
// 	double size = Floorsize(perEquity / (cost + riskPoints)); //max loss (0.1*balance = stp* size)  point*10 because we use 0.00001 as unit
// 	size = MathMin(size, MarketInfo(Symbol(), MODE_MAXLOT));
// 	size = MathMax(size, MarketInfo(Symbol(), MODE_MINLOT));
// 	return size;
// }
//+------------------------------------------------------------------+
double Floorsize(double x) {
	double x_mul100 = x * 100;
	double floorx = floor(x_mul100);
	double size = floorx / 100;
	size = MathMin(size, MarketInfo(Symbol(), MODE_MAXLOT));
	size = MathMax(size, MarketInfo(Symbol(), MODE_MINLOT));
	return size;
}
