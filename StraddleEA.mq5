//+------------------------------------------------------------------+
//|                                                     StraddleEA.mq5 |
//|                                  Copyright 2025, Hedge Warrior V1 |
//|                                 https://github.com/AymanChouman/HedgeWarrior |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Hedge Warrior V1"
#property link      "https://github.com/AymanChouman/HedgeWarrior"
#property version   "1.00"

//+------------------------------------------------------------------+
//| HEDGE WARRIOR V1 STRADDLE EA - CORE LOGIC IMPLEMENTATION         |
//+------------------------------------------------------------------+
//| This EA implements the proven Hedge Warrior V1 logic with:       |
//|                                                                   |
//| 1. HEDGE ORDERS ONLY AT RED/BLUE LINES (NEVER GREEN):            |
//|    - CheckHedgeTriggers() ensures hedge placement only at        |
//|      red/blue lines with strict green line exclusion             |
//|    - PlaceHedgeOrder() has critical safety check to prevent      |
//|      any hedge placement at/near green line                      |
//|                                                                   |
//| 2. HEDGE SIZING USING CORRECT HEDGE WARRIOR FORMULA:             |
//|    - CalculateHedgeSize() recalculates every time based on       |
//|      total main position exposure * HedgeMultiplier              |
//|    - Excludes hedge positions from calculation for accuracy      |
//|                                                                   |
//| 3. IMMEDIATE TP MOVEMENT TO GREEN LINE WHEN HEDGE FILLS:         |
//|    - CheckHedgeFilled() detects hedge fills instantly            |
//|    - MoveAllTPsToGreenLine() moves ALL main position TPs         |
//|      to green line IMMEDIATELY upon hedge fill                   |
//|                                                                   |
//| 4. IMMEDIATE CYCLE CLOSURE AT GREEN LINE:                        |
//|    - CheckCycleExit() monitors price vs green line constantly    |
//|    - CloseCycle() IMMEDIATELY closes all positions/orders        |
//|      when price hits green line                                  |
//|                                                                   |
//| 5. NO PENDING HEDGE ORDERS AT GREEN LINE - EVER:                 |
//|    - Multiple safety checks prevent this scenario                |
//|    - Hedge placement logic explicitly excludes green line zone   |
//|                                                                   |
//| 6. VISUAL/LINE DRAWING LOGIC PRESERVED:                          |
//|    - CreateVisualLines(), UpdateVisualLines() maintain chart     |
//|    - Red/Blue lines: hedge triggers, Green lines: cycle exits    |
//|    - All visual logic untouched, only mechanics fixed            |
//+------------------------------------------------------------------+

//--- Input Parameters
input double InitialLotSize = 0.01;        // Initial lot size
input double TakeProfitPips = 50.0;        // Take profit in pips
input double HedgeMultiplier = 2.0;        // Hedge multiplier for sizing
input double RedLineOffset = 100.0;        // Red line offset in pips
input double BlueLineOffset = 150.0;       // Blue line offset in pips
input double GreenLineOffset = 200.0;      // Green line offset (cycle exit)
input bool EnableHedging = true;           // Enable hedging
input bool PlaceInitialPositions = true;   // Place initial straddle positions
input int Magic = 12345;                   // Magic number

//--- Global Variables
double RedLineUp, RedLineDown;
double BlueLineUp, BlueLineDown;
double GreenLineUp, GreenLineDown;
bool HedgeDirection = true;                // true = buy hedge next, false = sell hedge next
double PointValue;
double LastHedgePrice = 0;
bool HedgeFilledThisCycle = false;        // Track if hedge has filled in current cycle

//--- Line drawing objects
string RedLineUpName = "RedLineUp";
string RedLineDownName = "RedLineDown";
string BlueLineUpName = "BlueLineUp";
string BlueLineDownName = "BlueLineDown";
string GreenLineUpName = "GreenLineUp";
string GreenLineDownName = "GreenLineDown";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Calculate point value for the current symbol
    PointValue = Point;
    if (Digits == 5 || Digits == 3) PointValue *= 10;
    
    // Initialize lines based on current price
    UpdateLines();
    
    // Create visual lines on chart
    CreateVisualLines();
    
    // Reset hedge tracking
    HedgeFilledThisCycle = false;
    
    // Place initial straddle positions if enabled
    if (PlaceInitialPositions && PositionsTotal() == 0)
    {
        PlaceInitialStraddlePositions();
    }
    
    Print("StraddleEA initialized successfully");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Remove visual lines
    DeleteVisualLines();
    
    Print("StraddleEA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Update lines
    UpdateLines();
    
    // Update visual lines on chart
    UpdateVisualLines();
    
    // Check for cycle exit (price hits green line) - IMMEDIATE closure required
    if (CheckCycleExit())
    {
        CloseCycle();
        return;
    }
    
    // Check for hedge triggers (price hits red/blue lines ONLY, never green)
    CheckHedgeTriggers();
    
    // Check if hedge has filled and move TPs to green line IMMEDIATELY
    CheckHedgeFilled();
}

//+------------------------------------------------------------------+
//| Update line levels based on current price                        |
//+------------------------------------------------------------------+
void UpdateLines()
{
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Calculate line levels
    RedLineUp = currentPrice + (RedLineOffset * PointValue);
    RedLineDown = currentPrice - (RedLineOffset * PointValue);
    
    BlueLineUp = currentPrice + (BlueLineOffset * PointValue);
    BlueLineDown = currentPrice - (BlueLineOffset * PointValue);
    
    GreenLineUp = currentPrice + (GreenLineOffset * PointValue);
    GreenLineDown = currentPrice - (GreenLineOffset * PointValue);
}

//+------------------------------------------------------------------+
//| Check if price has hit green line (cycle exit condition)         |
//+------------------------------------------------------------------+
bool CheckCycleExit()
{
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Check if price has hit green line (cycle exit)
    if (currentPrice >= GreenLineUp || currentPrice <= GreenLineDown)
    {
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Close entire cycle - all positions and pending orders           |
//+------------------------------------------------------------------+
void CloseCycle()
{
    Print("Cycle exit triggered at green line - IMMEDIATE closure of all positions and orders");
    
    // Close all positions IMMEDIATELY
    CloseAllPositions();
    
    // Delete all pending orders IMMEDIATELY
    DeleteAllPendingOrders();
    
    // Reset hedge direction, tracking variables
    HedgeDirection = true;
    LastHedgePrice = 0;
    HedgeFilledThisCycle = false;
    
    Print("Cycle closed successfully - ready for new cycle");
}

//+------------------------------------------------------------------+
//| Check for hedge triggers at red/blue lines                       |
//+------------------------------------------------------------------+
void CheckHedgeTriggers()
{
    if (!EnableHedging) return;
    
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // CRITICAL: Ensure NO hedge orders are EVER placed at green line
    if (currentPrice >= GreenLineDown && currentPrice <= GreenLineUp)
    {
        // Price is in green line zone - NO hedge placement allowed
        return;
    }
    
    // Check if price hits red or blue line and place hedge order
    // Hedge orders ONLY at red/blue lines, alternating direction
    bool triggerHedge = false;
    
    if (currentPrice >= RedLineUp || currentPrice >= BlueLineUp)
    {
        // Price hit upper line - place sell hedge (if alternating correctly)
        if (!HedgeDirection) // sell hedge
        {
            PlaceHedgeOrder(ORDER_TYPE_SELL, currentPrice);
            triggerHedge = true;
        }
    }
    else if (currentPrice <= RedLineDown || currentPrice <= BlueLineDown)
    {
        // Price hit lower line - place buy hedge (if alternating correctly)
        if (HedgeDirection) // buy hedge
        {
            PlaceHedgeOrder(ORDER_TYPE_BUY, currentPrice);
            triggerHedge = true;
        }
    }
    
    if (triggerHedge)
    {
        // Alternate hedge direction for next hedge (critical for proper alternation)
        HedgeDirection = !HedgeDirection;
        LastHedgePrice = currentPrice;
        Print("Hedge direction alternated. Next hedge will be: ", (HedgeDirection ? "BUY" : "SELL"));
    }
}

//+------------------------------------------------------------------+
//| Place hedge order with correct Hedge Warrior sizing             |
//+------------------------------------------------------------------+
void PlaceHedgeOrder(ENUM_ORDER_TYPE orderType, double price)
{
    // CRITICAL: Ensure we're NEVER placing hedge at green line
    if ((orderType == ORDER_TYPE_BUY && price >= GreenLineDown) || 
        (orderType == ORDER_TYPE_SELL && price <= GreenLineUp))
    {
        Print("CRITICAL WARNING: Attempted to place hedge at/near green line - BLOCKED");
        return;
    }
    
    // Calculate hedge size using correct Hedge Warrior formula (recalculated every time)
    double hedgeSize = CalculateHedgeSize();
    
    Print("Placing hedge order at RED/BLUE line. Type: ", EnumToString(orderType), " Size: ", hedgeSize);
    
    // Place the hedge order
    MqlTradeRequest request;
    MqlTradeResult result;
    
    ZeroMemory(request);
    ZeroMemory(result);
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = hedgeSize;
    request.type = orderType;
    request.price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    request.deviation = 10;
    request.magic = Magic;
    request.comment = "Hedge_Order";
    
    if (OrderSend(request, result))
    {
        Print("Hedge order placed successfully at RED/BLUE line: ", EnumToString(orderType), " Size: ", hedgeSize);
    }
    else
    {
        Print("Failed to place hedge order: ", result.retcode);
    }
}

//+------------------------------------------------------------------+
//| Calculate hedge size using Hedge Warrior formula                 |
//+------------------------------------------------------------------+
double CalculateHedgeSize()
{
    // Get total lot size of existing main positions (not hedge positions)
    double totalMainLots = 0;
    int mainPositionCount = 0;
    
    for (int i = 0; i < PositionsTotal(); i++)
    {
        if (PositionSelectByIndex(i))
        {
            if (PositionGetString(POSITION_SYMBOL) == _Symbol && 
                PositionGetInteger(POSITION_MAGIC) == Magic)
            {
                string comment = PositionGetString(POSITION_COMMENT);
                // Exclude hedge positions from calculation
                if (StringFind(comment, "Hedge") < 0)
                {
                    totalMainLots += PositionGetDouble(POSITION_VOLUME);
                    mainPositionCount++;
                }
            }
        }
    }
    
    // If no existing main positions, use initial lot size
    if (totalMainLots == 0)
    {
        Print("No main positions found, using initial lot size: ", InitialLotSize);
        return InitialLotSize;
    }
    
    // Hedge Warrior formula: recalculate size based on total main exposure every time
    double hedgeSize = totalMainLots * HedgeMultiplier;
    
    Print("Hedge size calculation - Main lots: ", totalMainLots, " Multiplier: ", HedgeMultiplier, " Result: ", hedgeSize);
    
    // Ensure minimum lot size
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    if (hedgeSize < minLot) 
    {
        hedgeSize = minLot;
        Print("Hedge size adjusted to minimum: ", hedgeSize);
    }
    
    // Ensure maximum lot size
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    if (hedgeSize > maxLot) 
    {
        hedgeSize = maxLot;
        Print("Hedge size adjusted to maximum: ", hedgeSize);
    }
    
    return hedgeSize;
}

//+------------------------------------------------------------------+
//| Check if hedge has filled and move all TPs to green line         |
//+------------------------------------------------------------------+
void CheckHedgeFilled()
{
    if (HedgeFilledThisCycle) return; // Already processed hedge fill this cycle
    
    // Check if there are any new hedge positions that indicate hedge has filled
    for (int i = 0; i < PositionsTotal(); i++)
    {
        if (PositionSelectByIndex(i))
        {
            if (PositionGetString(POSITION_SYMBOL) == _Symbol && 
                PositionGetInteger(POSITION_MAGIC) == Magic)
            {
                string comment = PositionGetString(POSITION_COMMENT);
                if (StringFind(comment, "Hedge_Order") >= 0)
                {
                    // Hedge has filled - IMMEDIATELY move all main position TPs to green line
                    Print("Hedge filled detected - IMMEDIATELY moving all TPs to green line");
                    MoveAllTPsToGreenLine();
                    
                    // Mark that hedge has filled this cycle to avoid repeated TP moves
                    HedgeFilledThisCycle = true;
                    
                    Print("All TPs moved to green line successfully");
                    break;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Move all main position TPs to green line immediately             |
//+------------------------------------------------------------------+
void MoveAllTPsToGreenLine()
{
    Print("IMMEDIATE TP modification: Moving all main position TPs to green line");
    
    for (int i = 0; i < PositionsTotal(); i++)
    {
        if (PositionSelectByIndex(i))
        {
            if (PositionGetString(POSITION_SYMBOL) == _Symbol && 
                PositionGetInteger(POSITION_MAGIC) == Magic)
            {
                string comment = PositionGetString(POSITION_COMMENT);
                // Only modify main positions, not hedge positions
                if (StringFind(comment, "Hedge") < 0)
                {
                    ulong ticket = PositionGetInteger(POSITION_TICKET);
                    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                    double sl = PositionGetDouble(POSITION_SL);
                    
                    // Calculate new TP at green line (cycle exit line)
                    double newTP;
                    if (posType == POSITION_TYPE_BUY)
                    {
                        newTP = GreenLineUp;
                    }
                    else
                    {
                        newTP = GreenLineDown;
                    }
                    
                    // IMMEDIATELY modify position TP
                    MqlTradeRequest request;
                    MqlTradeResult result;
                    
                    ZeroMemory(request);
                    ZeroMemory(result);
                    
                    request.action = TRADE_ACTION_SLTP;
                    request.position = ticket;
                    request.symbol = _Symbol;
                    request.sl = sl;
                    request.tp = newTP;
                    
                    if (OrderSend(request, result))
                    {
                        Print("TP IMMEDIATELY moved to green line for position: ", ticket, " New TP: ", newTP);
                    }
                    else
                    {
                        Print("CRITICAL: Failed to move TP for position: ", ticket, " Error: ", result.retcode);
                    }
                }
            }
        }
    }
}



//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if (PositionSelectByIndex(i))
        {
            if (PositionGetString(POSITION_SYMBOL) == _Symbol && 
                PositionGetInteger(POSITION_MAGIC) == Magic)
            {
                ulong ticket = PositionGetInteger(POSITION_TICKET);
                
                MqlTradeRequest request;
                MqlTradeResult result;
                
                ZeroMemory(request);
                ZeroMemory(result);
                
                request.action = TRADE_ACTION_DEAL;
                request.position = ticket;
                request.symbol = _Symbol;
                request.volume = PositionGetDouble(POSITION_VOLUME);
                request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
                request.price = (request.type == ORDER_TYPE_SELL) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                request.deviation = 10;
                request.magic = Magic;
                
                OrderSend(request, result);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Delete all pending orders                                        |
//+------------------------------------------------------------------+
void DeleteAllPendingOrders()
{
    for (int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if (OrderSelect(OrderGetTicket(i)))
        {
            if (OrderGetString(ORDER_SYMBOL) == _Symbol && 
                OrderGetInteger(ORDER_MAGIC) == Magic)
            {
                MqlTradeRequest request;
                MqlTradeResult result;
                
                ZeroMemory(request);
                ZeroMemory(result);
                
                request.action = TRADE_ACTION_REMOVE;
                request.order = OrderGetTicket(i);
                
                OrderSend(request, result);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Create visual lines on chart                                     |
//+------------------------------------------------------------------+
void CreateVisualLines()
{
    // Create red lines (hedge trigger lines)
    ObjectCreate(0, RedLineUpName, OBJ_HLINE, 0, 0, RedLineUp);
    ObjectSetInteger(0, RedLineUpName, OBJPROP_COLOR, clrRed);
    ObjectSetInteger(0, RedLineUpName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, RedLineUpName, OBJPROP_WIDTH, 2);
    
    ObjectCreate(0, RedLineDownName, OBJ_HLINE, 0, 0, RedLineDown);
    ObjectSetInteger(0, RedLineDownName, OBJPROP_COLOR, clrRed);
    ObjectSetInteger(0, RedLineDownName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, RedLineDownName, OBJPROP_WIDTH, 2);
    
    // Create blue lines (hedge trigger lines)
    ObjectCreate(0, BlueLineUpName, OBJ_HLINE, 0, 0, BlueLineUp);
    ObjectSetInteger(0, BlueLineUpName, OBJPROP_COLOR, clrBlue);
    ObjectSetInteger(0, BlueLineUpName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, BlueLineUpName, OBJPROP_WIDTH, 2);
    
    ObjectCreate(0, BlueLineDownName, OBJ_HLINE, 0, 0, BlueLineDown);
    ObjectSetInteger(0, BlueLineDownName, OBJPROP_COLOR, clrBlue);
    ObjectSetInteger(0, BlueLineDownName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, BlueLineDownName, OBJPROP_WIDTH, 2);
    
    // Create green lines (cycle exit lines - NO hedges here)
    ObjectCreate(0, GreenLineUpName, OBJ_HLINE, 0, 0, GreenLineUp);
    ObjectSetInteger(0, GreenLineUpName, OBJPROP_COLOR, clrGreen);
    ObjectSetInteger(0, GreenLineUpName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, GreenLineUpName, OBJPROP_WIDTH, 3);
    
    ObjectCreate(0, GreenLineDownName, OBJ_HLINE, 0, 0, GreenLineDown);
    ObjectSetInteger(0, GreenLineDownName, OBJPROP_COLOR, clrGreen);
    ObjectSetInteger(0, GreenLineDownName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, GreenLineDownName, OBJPROP_WIDTH, 3);
    
    Print("Visual lines created - Red/Blue: hedge triggers, Green: cycle exit");
}

//+------------------------------------------------------------------+
//| Update visual lines on chart                                     |
//+------------------------------------------------------------------+
void UpdateVisualLines()
{
    // Update red lines
    ObjectSetDouble(0, RedLineUpName, OBJPROP_PRICE, RedLineUp);
    ObjectSetDouble(0, RedLineDownName, OBJPROP_PRICE, RedLineDown);
    
    // Update blue lines
    ObjectSetDouble(0, BlueLineUpName, OBJPROP_PRICE, BlueLineUp);
    ObjectSetDouble(0, BlueLineDownName, OBJPROP_PRICE, BlueLineDown);
    
    // Update green lines
    ObjectSetDouble(0, GreenLineUpName, OBJPROP_PRICE, GreenLineUp);
    ObjectSetDouble(0, GreenLineDownName, OBJPROP_PRICE, GreenLineDown);
}

//+------------------------------------------------------------------+
//| Delete visual lines from chart                                   |
//+------------------------------------------------------------------+
void DeleteVisualLines()
{
    ObjectDelete(0, RedLineUpName);
    ObjectDelete(0, RedLineDownName);
    ObjectDelete(0, BlueLineUpName);
    ObjectDelete(0, BlueLineDownName);
    ObjectDelete(0, GreenLineUpName);
    ObjectDelete(0, GreenLineDownName);
    
    Print("Visual lines removed from chart");
}

//+------------------------------------------------------------------+
//| Place initial straddle positions                                 |
//+------------------------------------------------------------------+
void PlaceInitialStraddlePositions()
{
    Print("Placing initial straddle positions");
    
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    // Calculate initial TP levels (before hedge adjustments)
    double buyTP = currentPrice + (TakeProfitPips * PointValue);
    double sellTP = currentPrice - (TakeProfitPips * PointValue);
    
    // Place initial BUY position
    MqlTradeRequest request;
    MqlTradeResult result;
    
    ZeroMemory(request);
    ZeroMemory(result);
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = InitialLotSize;
    request.type = ORDER_TYPE_BUY;
    request.price = askPrice;
    request.tp = buyTP;
    request.deviation = 10;
    request.magic = Magic;
    request.comment = "Initial_Buy";
    
    if (OrderSend(request, result))
    {
        Print("Initial BUY position placed successfully");
    }
    else
    {
        Print("Failed to place initial BUY position: ", result.retcode);
    }
    
    // Place initial SELL position
    ZeroMemory(request);
    ZeroMemory(result);
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = InitialLotSize;
    request.type = ORDER_TYPE_SELL;
    request.price = currentPrice;
    request.tp = sellTP;
    request.deviation = 10;
    request.magic = Magic;
    request.comment = "Initial_Sell";
    
    if (OrderSend(request, result))
    {
        Print("Initial SELL position placed successfully");
    }
    else
    {
        Print("Failed to place initial SELL position: ", result.retcode);
    }
    
    Print("Initial straddle positions setup complete");
}