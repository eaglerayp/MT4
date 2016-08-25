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
extern double fallbackRate = 0.2;
const double totalCloseRate = 1.0;

// assume maximum concurreny trade is 100
const int maxConcurrentTrade = 100;
const double ten = 10;
const double zero = 0.0;
const double one = 1.0;

double maxProfitTracker[100];
double maxLossTracker[100];
bool tracked[100];
double threshold[100];
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
	// Print("lot size:" + OrderLots());
	// Print("Margin size:" + MarketInfo(OrderSymbol(), MODE_MARGINREQUIRED));
	double marginCost = double(MarketInfo(OrderSymbol(), MODE_MARGINREQUIRED));
	double onePercent = OrderLots() * marginCost * 0.01;
	// Print(onePercent);
	return onePercent;
}

//+------------------------------------------------------------------+
int hashIndex(int ticket) {
	return ticket % maxConcurrentTrade;
}

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
			logInfo(ticket, index);
			checkProfit(ticket, index);
			// check fallback
			// check time
			checkTime(ticket, index);
		}//end select
	}//end for
}
//+------------------------------------------------------------------+
void logInfo(int ticket, int index) {
	if (tracked[index]){
		return;
	}

	printf("ticket :" + ticket + ", first tracked");
	double onePercent = getOnePercent();
	printf("lot size :" + OrderLots() + ", one percent treshold:" + onePercent);
	tracked[index] = true;
	threshold[index] = onePercent;
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

	if (profit < -ten * onePercentThreshold) {
		printf("ticket:" + ticket + ", close by check profit:" + profit);
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
	// Log message during the trade:
	// 1. max loss
	// 3. max profit
	printf("ticket:" + ticket + ", close end");
	printf("max profit:" + maxProfitTracker[index]);
	printf("max loss:" + maxLossTracker[index]);
	maxProfitTracker[index] = zero;
	maxLossTracker[index] = zero;
	tracked[index] = false;
	threshold[index] = zero;

}
//+------------------------------------------------------------------+
// void checkOrderFallbackProfit() {
// 	if (ordertype > 0) {
// 		if (ordertype == 1) { //buy
// 			// set max
// 			if (Bid > max_profit_value) {
// 				max_profit_value = Bid;
// 				double profit = max_profit_value-start_value;
// 				leave_value = max_profit_value - (profit * fallback_rate[fallback_index]);
// 				//printf("buy max:"+max_profit_value+";profit:"+profit+"leave:"+leave_value);
// 			}
// 			if (allowfallbackClose && max_profit_value > threshold ) {
// 				if ( Bid < leave_value) {
// 					printf("close by fallback:" + fallback_rate[fallback_index] + " Max tick value:" + max_profit_value + " leave value:" + leave_value);
// 					if (fallback_index == 0) { //close 50%
// 					   double profit = max_profit_value-start_value;
// 						leave_value = max_profit_value - (profit * fallback_rate[++fallback_index]);
// 						CloseAllOrder(small_slip, half_closerate);
// 					} else { //close all and reset parameters
// 						CloseAllOrder(small_slip, totalCloseRate);
// 						fallback_index = 0;
// 						allowfallbackClose = false;
// 						max_profit_value = 9999;
// 						leave_value = 9999;
// 						threshold = 9999;
// 						ordertype = 0;
// 						start_value = 9999;
// 					}
// 				}
// 			}
// 		} else { //sell
// 			// set max
// 			if (Ask < max_profit_value) {
// 				max_profit_value = Ask;
// 				double profit = start_value - max_profit_value;
// 				leave_value = max_profit_value + (profit * fallback_rate[fallback_index]);
// 			   //printf("sell max:"+max_profit_value+";profit:"+profit+"leave:"+leave_value);
// 			}
// 			if (allowfallbackClose && max_profit_value < threshold) {
// 				if (Ask > leave_value) {
// 					printf("close by fallback" + fallback_rate[fallback_index] + " Max tick value:" + max_profit_value + " leave value:" + leave_value);
// 					if (fallback_index == 0) { //close 50%
// 						CloseAllOrder(small_slip, half_closerate);
// 						double profit = start_value- max_profit_value;
// 						leave_value = max_profit_value + (profit * fallback_rate[++fallback_index]);
// 					} else {  //close all and reset parameters
// 						CloseAllOrder(small_slip, totalCloseRate);
// 						fallback_index = 0;
// 						allowfallbackClose = false;
// 						max_profit_value = 9999;
// 						leave_value = 9999;
// 						threshold = 9999;
// 						start_value = 9999;
// 						ordertype = 0;
// 					}
// 				}
// 			}
// 		}
// 	}
// }
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

//+------------------------------------------------------------------+
// void checkStoploss() {
// 	int total = OrdersTotal();
// 	double currentTime = TimeCurrent();
// 	double five_mins = 5 * one_min;
// 	for (int i = 0; i < total; i++) {
// 		bool select = OrderSelect(i, SELECT_BY_POS , MODE_TRADES);
// 		if (select) {
// 			string sym_close = OrderSymbol();
// 			double Orderopen = OrderOpenTime();
// 			if (sym_close == sym && currentTime > Orderopen + five_mins) {
// 				if (OrderType() == OP_BUY && Bid < stoploss_value) {
// 					CloseAllOrder(big_slip, totalCloseRate);
// 					// only in post stage do reverse trade
// 					if (InPostStage) {
// 						reverse_event = true;
// 						Sell(sym, lots_size, "reverse Sell", magicnum, big_slip, reverse_stage);
// 						printf("close by stoploss, big slip");
// 					}
// 				} else if (OrderType() == OP_SELL && Ask > stoploss_value) {
// 					CloseAllOrder(big_slip, totalCloseRate);
// 					// do reverse trade
// 					if (InPostStage) {
// 						reverse_event = true;
// 						Buy(sym, lots_size, "reverse Buy", magicnum, big_slip, reverse_stage);
// 						printf("close by stoploss, big slip");
// 					}
// 				}
// 			}
// 		}
// 	}//end select
// //end for
// }
//+------------------------------------------------------------------+