# 🥐 Smart Bakery Food Waste Reduction System

**Final Year Project (FYP) – Comprehensive Documentation**

---

## 📌 1. Introduction

The **Smart Bakery Food Waste Reduction System** is an **intelligent demand prediction platform** designed for a **single bakery** to minimize overproduction and optimize daily operations using machine learning and data-driven insights.

### System Focus: ONE BAKERY (Realistic Implementation)

**Scope:** This system is designed for **one bakery operation** to ensure:
- Realistic complexity
- Manageable data collection
- Practical implementation and testing
- Focus on depth over breadth

### Core Architecture

The system is built around **ONE MAIN OBJECTIVE:**

| Core Component | Purpose |
|---|---|
| 🧠 **Intelligent Demand Prediction (MAIN)** | Predict next-day bread demand by category with detailed accuracy |
| 📦 **Inventory Management (SUPPORT)** | Track actual vs predicted to improve future predictions |
| 🛒 **POS Simulation (SUPPORT)** | Generate realistic sales data for testing & learning |
| ♻️ **Leftover Management (SIMPLE)** | Donate unavoidable waste to charity organizations |

### Overall Vision
**"Build a smart demand prediction engine that learns from daily operations to minimize overproduction and waste."**

---

## 🎯 2. Problem Statement

### The Bread Waste Challenge in Bakeries

Bakeries face a fundamental problem: **How much bread should we bake tomorrow?**

| Challenge | Impact |
|-----------|--------|
| 📊 **No Data-Driven Decisions** | Bakers rely on intuition and past experience |
| 📈 **Demand Unpredictable** | Weather, events, day of week all affect sales differently |
| 🗑️ **Overproduction** | Baking too much leads to daily waste |
| ❌ **Ingredient Waste** | Unused flour, butter, and other ingredients due to over-ordering |
| 💰 **Financial Loss** | Daily waste of unsold inventory directly impacts profit margin |
| 🌍 **Environmental Impact** | Discarded bread contributes to landfill waste |

### Real-World Example: Single Bakery

```
TYPICAL BAKERY (NO PREDICTION SYSTEM):

Monday (Rainy Day):
├─ Planned Production: 100 croissants (based on last Monday)
├─ Actual Demand: 55 croissants (rainy weather reduced customers)
├─ Leftover & Waste: 45 croissants (45%)
└─ Loss: ~$67.50 in wasted ingredients + labor

Wednesday (Special Event):
├─ Planned Production: 100 croissants (standard day)
├─ Actual Demand: 180 croissants (unexpected event = high demand)
├─ Lost Sales Opportunity: 80 customers turned away
└─ Lost Revenue: ~$156

Why This Happens:
❌ No consideration for weather forecasts
❌ No tracking of special events or holidays
❌ No analysis of demand patterns per day of week
❌ Just "bake same amount as yesterday"
```

### Consequences of No Prediction

- 💰 **Revenue Loss:** 20-30% of daily ingredients wasted
- 🌍 **Environmental:** ~365 kg of wasted bread per year (typical bakery)
- ⚙️ **Operational:** Inefficient staff scheduling based on unpredictable demand
- 📦 **Supply Chain:** Excess ingredient ordering leading to spoilage

---

## 💡 3. Proposed Solution

### Core Strategy: Intelligent Demand Prediction

**Main Objective:** Use machine learning to predict next-day demand **accurately and in detail**, helping the bakery manager:
✅ Know exactly how much of each bread type to make tomorrow  
✅ Optimize ingredient purchasing  
✅ Minimize overproduction waste  
✅ Maximize revenue and profitability  

### How It Works: The Prediction Advantage

```
WITHOUT PREDICTION:
When?: Today evening
→ Baker guesses: "I'll bake 100 croissants tomorrow"
→ Based on: "I usually bake 100"
→ Result: May waste 30-40 units, or lose 20 sales

WITH PREDICTION:
When?: Today evening (or early morning before production)
→ System predicts: "Tomorrow is Friday + Sunny = 120 croissants"
→ Based on: Historical data + weather + day type + events
→ Input Factors:
   ├─ Last 30 days croissant sales patterns
   ├─ Friday always has higher demand (+15%)
   ├─ Sunny weather increases foot traffic (+10%)
   └─ No holidays or events
→ Result: Accurate prediction, minimal waste ✅
```

### Two-Part Defense Strategy

**Part 1: Waste PREVENTION (Proactive)**
- Use prediction to determine optimal daily production quantities
- Reduce overproduction at the source
- Optimize ingredient ordering based on predicted demand

**Part 2: Waste RECOVERY (Reactive) - Secondary**
- For unavoidable leftover → Donate to charity organizations
- No discounting needed; focus on social responsibility
- Leftover tracking provides data for ML model improvement

---

## 🧩 4. System Architecture

The system is organized around **ONE CORE MODULE** (Prediction) with supporting components:

### ⭐ 4.1 Intelligent Demand Prediction System (CORE MODULE)

**This is the HEART of the system.** Everything else supports this.

---

#### 📊 4.1.1 Prediction Objective

**What:** Predict tomorrow's demand for each bread category  
**Why:** Enable smart production decisions that minimize waste  
**When:** Every evening (system runs before next day's production)  
**Output:** Specific production recommendations + ingredient requirements  

**Example Prediction Output:**

```
🕐 PREDICTION TIME: Today 6:00 PM (for Tomorrow)

CONTEXT:
├─ Tomorrow: Friday, sunny, no events
├─ Current inventory levels available
└─ Ingredient stock: Check

PREDICTION RESULTS:
┌─────────────────────────────────────────┐
│ BREAD CATEGORY │ PREDICTED │ RECOMMEND │
├─────────────────────────────────────────┤
│ Croissants     │   110     │   115     │
│ Sweet Bread    │    65     │    68     │
│ Loaves         │    42     │    45     │
│ Ciabatta       │    28     │    30     │
└─────────────────────────────────────────┘

INGREDIENT REQUIREMENTS FOR RECOMMENDED PRODUCTION:
├─ Flour: 35 kg (current stock: 38 kg ✅)
├─ Butter: 8 kg (current stock: 5 kg ⚠️)
├─ Sugar: 4 kg (current stock: 6 kg ✅)
└─ Yeast: 500g (current stock: 300g ⚠️)

⚠️ CONSTRAINT DETECTED:
└─ Butter insufficient for full recommendation
   → Adjusted recommendation: 100 croissants instead of 115
   → New flour need: 32 kg
   → New butter need: 7 kg (not available)
```

---

#### 📥 4.1.2 Input Features (Data used for Prediction)

This is where the **sophisticated intelligence** comes in. The model considers:

##### Category A: Historical Sales Data

```
📊 PAST 30 DAYS ANALYSIS

For each bread category, the system tracks:

CROISSANTS EXAMPLE:
├─ Day 1 (Mon): Produced 100, Sold 85, Leftover 15
├─ Day 2 (Tue): Produced 95, Sold 88, Leftover 7
├─ ...
├─ Day 29 (Fri): Produced 110, Sold 105, Leftover 5
└─ Day 30 (Sat): Produced 125, Sold 119, Leftover 6

SYSTEM LEARNS:
├─ Average daily demand: 95 croissants
├─ Demand variability: 10-15 units
├─ Leftover patterns: Lower on Fridays/Saturdays
└─ Trend: Any upward/downward trend in past 30 days
```

##### Category B: Time-Based Features

```
🗓️ TEMPORAL PATTERNS

Day of Week Analysis:
├─ Monday: -5% (weekend customers don't return immediately)
├─ Tuesday: -3% (slight slow-down from Monday)
├─ Wednesday: +2% (mid-week stable)
├─ Thursday: +5% (weekend preparation begins)
├─ Friday: +15% ⬆️ (weekend anticipated)
├─ Saturday: +20% ⬆️ (peak weekend day)
└─ Sunday: +8% (family purchases)

Seasonal Patterns:
├─ Summer (June-Aug): -10% (less demand, more eating out)
├─ Spring (Mar-May): +5% (weather improves)
├─ Autumn (Sep-Nov): +8% (back to routine)
└─ Winter (Dec-Feb): +15% (comfort food season)

Special Occasions:
├─ Christmas/New Year: +40-50%
├─ Easter: +25-30%
├─ RAMADAN: -30% (fasting period)
├─ Back-to-school: +15%
└─ Summer holidays: -15%
```

##### Category C: External Factors

```
🌦️ WEATHER IMPACT

Weather Type Impact on Demand:
├─ Sunny day: +10% (more customers on street)
├─ Rainy day: -15% (fewer customers, stay home)
├─ Cloudy day: No change (neutral)
├─ Very hot (>32°C): -8% (reduced bread interest)
└─ Winter snow: -20% (transportation issues)

📅 HOLIDAYS & EVENTS (Via Google Calendar API)

How It Works:
├─ System calls Google Calendar API for "Tomorrow"
├─ Query: Is tomorrow a public holiday? School holiday? Special event?
├─ Result: Returns holiday status + type
└─ Action: ML model applies appropriate weight adjustment

Holiday Impact on Demand:
├─ National holidays: +25-30% weight
│  └─ Example: "Tomorrow is Independence Day → +30% demand expected"
│
├─ School holidays: -10% weight
│  └─ Decreased customer flow (families on vacation, shop elsewhere)
│
└─ Religious holidays (Ramadan, Eid, etc.): Variable
   └─ Custom weights per region/bakery

Example Prediction with Calendar Integration:
Tomorrow: Friday (normally +15%)
         + Sunny weather (+10%)
         + Public Holiday (DETECTED via Calendar API: +30%)
         
Final Weight Adjustment: +15% (Friday) × +10% (Sunny) × +30% (Holiday)
↓
Predicted Demand: 100 base × 1.55 = 155 croissants
Recommendation: "Tomorrow is a holiday; I recommend increasing 
                Croissant production by 55%."

Local Events:
├─ University exams: +20% (can be tracked in calendar)
├─ Sports events: ±15% (depends on home/away)
├─ Concerts/festivals: +30-40%
└─ Lockdowns/restrictions: -30-50%
```

##### Category D: Operational Inventory Data

```
📦 CURRENT CAPACITY & STOCK

Ingredient Availability:
├─ Flour stock: 38 kg (enough for 95 Croissants)
├─ Butter stock: 5 kg (only enough for 80 Croissants)
├─ Sugar stock: 6 kg ✅
└─ Yeast stock: 300g (limited)

Based on Ingredient Constraints:
└─ Max production for croissants: 80 units (butter-limited)
   → System adjusts prediction if >80 recommended

Storage Capacity:
├─ Shelf space for croissants: 150 units max
├─ Oven capacity: allows 120 units per batch
└─ If storage full → Reduce production recommendation
```

---

#### 📤 4.1.3 Prediction Output

The system outputs THREE levels of information:

**Level 1: Demand Prediction (per category)**
```
Tomorrow's Predicted Demand:
├─ Croissants: 110 units (confidence: 87%)
├─ Sweet Bread: 65 units (confidence: 92%)
├─ Loaves: 42 units (confidence: 84%)
└─ Ciabatta: 28 units (confidence: 78%)
```

**Level 2: Production Recommendation**
```
Recommended Production (after inventory/capacity check):
├─ Croissants: 115 units (predicted 110 + 5% buffer)
├─ Sweet Bread: 68 units (predicted 65 + 5% buffer)
├─ Loaves: 45 units (predicted 42 + 7% buffer)
└─ Ciabatta: 30 units (predicted 28 + 7% buffer)
```

**Level 3: Ingredient Requirements**
```
For Recommended Quantities, Baker Needs:
├─ Flour: 35 kg (per recipes × quantities)
├─ Butter: 8 kg ⚠️ (INSUFFICIENT - only 5 kg available)
├─ Sugar: 4 kg ✅
├─ Yeast: 500 g ⚠️ (LIMITED - only 300 g available)
└─ Salt: 300 g ✅

⚠️ ADJUSTMENTS NEEDED:
If unable to source more supplies:
└─ Reduced recommendation: 100 croissants (butter constraint)
```

---

#### 🎯 4.1.4 What is Prediction Confidence?

**Confidence Level:** The model's certainty about its prediction (0-100%)

```
WHAT IT MEANS:

Confidence: 87% ← "I'm 87% sure the demand will be 110 croissants"
                  (17% uncertainty - demand could be 95-125 range)

Confidence: 92% ← "I'm 92% sure (high certainty)"
                  (8% uncertainty - narrow range prediction)

Confidence: 70% ← "I'm 70% sure (lower certainty)"
                  (30% uncertainty - demand could vary widely)
```

**What IMPACTS Prediction Confidence?**

```
FACTORS THAT INCREASE CONFIDENCE (↑):

✅ 1. HISTORICAL DATA CLARITY
   ├─ Similar past days show clear patterns
   ├─ Monday croissant sales consistently 80-100 units
   ├─ Low variance = high confidence
   └─ Effect: +5-10% confidence boost

✅ 2. CERTAIN EXTERNAL CONDITIONS  
   ├─ Weather forecast is accurate & available
   ├─ Holiday is officially confirmed (via calendar API)
   ├─ Special events are pre-announced
   └─ Effect: +10-15% confidence boost

✅ 3. STABLE SEASONAL PERIOD
   ├─ Spring/Summer/Fall/Winter patterns are known
   ├─ Time of year matches many past years
   ├─ No unusual circumstances
   └─ Effect: +5% confidence boost

✅ 4. MODEL HAS LEARNED WELL
   ├─ After 30 days: Model learned this bakery's pattern
   ├─ After 90 days: Specialized model with good accuracy
   ├─ After 1 year: Excellent predictions for recurring patterns
   └─ Effect: Confidence gradually increases over time

FACTORS THAT DECREASE CONFIDENCE (↓):

❌ 1. MISSING HISTORICAL DATA
   ├─ First week: Only few days of history available
   ├─ Unknown patterns for this bakery
   ├─ Model has to guess more
   └─ Effect: -10-20% confidence reduction

❌ 2. UNCERTAIN EXTERNAL CONDITIONS
   ├─ Weather forecast is vague ("might rain")
   ├─ Approaching holiday but not confirmed yet
   ├─ Unusual events not in calendar
   └─ Effect: -15-25% confidence reduction

❌ 3. ANOMALOUS SITUATIONS
   ├─ Unprecedented weather (never seen before)
   ├─ Emergency closing possibility
   ├─ Major city event affecting foot traffic
   └─ Effect: -20-30% confidence reduction

❌ 4. CONFLICTING FACTORS
   ├─ Friday (high demand) + Heavy rain (-15%) = conflicting
   ├─ Holiday (+30%) + Rainy (-15%) = partially offsetting
   ├─ Model uncertain which effect dominates
   └─ Effect: -5-15% confidence reduction
```

**Real Examples:**

```
SCENARIO 1: HIGH CONFIDENCE
═══════════════════════════

Tomorrow: Friday (regular Friday, no special event)
Weather: Sunny (confident forecast)
History: 30 days of Friday data available
Season: Spring (familiar season)

PREDICTION PROCESS:
├─ Friday pattern known: +15% → 87.5 base demand
├─ Sunny weather confirmed: +10% → 96.25 adjusted
├─ Spring pattern stable: +0% → still 96.25
├─ 30 days history available: No data gap penalty
└─ Conflicting factors: None

RESULT: 140 units (confidence: 92%)
WHY HIGH: All factors clear, model confident

───────────────────────────────────────

SCENARIO 2: MEDIUM CONFIDENCE
═══════════════════════════════

Tomorrow: First Monday of the month
Weather: "Possible rain" (uncertain forecast)
History: 14 days available (only 2 Mondays seen)
Season: Spring (familiar)

PREDICTION PROCESS:
├─ Monday pattern unclear: -5% (high uncertainty)
├─ Weather uncertain: -15% IF rain, +0% IF clear (model guesses)
├─ Only 2 Mondays in history: penalty for low sample size
├─ Conflicting factors: Rain effect vs Monday pattern
└─ Result: Model hedges its bets

RESULT: 78 units (confidence: 73%)
WHY MEDIUM: Uncertain weather + limited Monday data

───────────────────────────────────────

SCENARIO 3: LOW CONFIDENCE
══════════════════════════

Tomorrow: First day of year (New Year) + Blizzard
Weather: "Heavy snow expected" (major disruption)
History: Only 2 days of data (system just started)
Season: Winter (rarely seen by new system)

PREDICTION PROCESS:
├─ New Year holiday: +40-50% (but system unsure)
├─ Blizzard: Could be -50% or more (unprecedented)
├─ Only 2 days history: Severe data gap
├─ Conflicting factors: Holiday boost vs blizzard risk
├─ System highly uncertain
└─ Prediction very conservative

RESULT: 55 units (confidence: 58%)
WHY LOW: Too many unknowns, not enough history
```

**How Manager Should Use Confidence:**

```
CONFIDENCE ≥ 90%:
└─ Baker can trust prediction
└─ Produce recommended amount with confidence

CONFIDENCE 75-89%:
└─ Reasonable prediction, but prepare backup plan
└─ Maybe order extra ingredients just in case
└─ Monitor (weather changes, customer feedback)

CONFIDENCE < 75%:
└─ Prediction less reliable
└─ Baker should use judgment + experience
└─ Consider ordering backup ingredients
└─ Prepare discount strategy if overstocked
```

**Confidence Level Improves Over Time:**

```
SYSTEM MATURITY:

WEEK 1 (Starting):      Confidence: 65-75% (new, limited data)
WEEK 2-3 (Learning):    Confidence: 70-80% (patterns emerging)
WEEK 4-6 (Settling):    Confidence: 78-85% (reliable predictions)
MONTH 3 (Optimized):    Confidence: 85-92% (very accurate)
MONTH 6+ (Specialized): Confidence: 90-95% (bakery-specific expert)
YEAR 1+ (Expert):       Confidence: 93-98% (highly specialized)

→ System becomes MORE confident as it learns your bakery!
```

---

#### 🧠 4.1.5 Model Type

**Recommended Model: Random Forest Regression**

```
WHY RANDOM FOREST?

✅ Handles non-linear patterns
   └─ Weather impact isn't simple (sunny +10%, but too hot is -8%)

✅ Captures feature interactions
   └─ Friday + Sunny + No rain = Even higher demand
   └─ Not just additive: Friday (+15%) + Sunny (+10%) ≠ +25%

✅ Robust to outliers
   └─ Handles rare events (concerts, accidents) better

✅ Feature importance ranking
   └─ Shows which factors matter most for prediction
   └─ Useful for business insights

✅ Naturally handles categorical data
   └─ Day of week, weather condition directly as input

ALTERNATIVE: Linear Regression (Baseline)
├─ Simpler but less accurate
├─ Good for starting point / comparison
└─ Can set as baseline model for evaluation
```

---

#### 🔄 4.1.6 Prediction Learning Loop

**This shows how the system improves over time:**

```
DAY 1:
┌──────────────────────────────────┐
│ System Predicts: 100 Croissants  │
└──────────────────────────────────┘
          ↓
          ↓ Baker produces 100 croissants
          ↓
          ↓ [Throughout the day]
          ↓
          ↓ Actual demand occurs
          ↓
┌──────────────────────────────────┐
│ Actual Sales: 85 Croissants      │
│ Leftover: 15 Croissants          │
└──────────────────────────────────┘
          ↓
          ↓ [End of day]
          ↓
ERROR CALCULATION:
├─ Predicted: 100
├─ Actual: 85
├─ Error: 15 units (15% error)
└─ Error Rate: Absolute % Error

          ↓
          ↓ ML MODEL LEARNS
          ↓
MODEL UPDATES:
├─ Analyzed: Why was prediction off?
├─ Checked: Was there rain? (yes, -15% factor)
├─ Checked: Was it Monday? (yes, -5% factor)
├─ Updated: Weights adjusted for rain + Monday pattern
└─ Result: Next Monday prediction will be more accurate

          ↓
DAY 2:
New prediction uses updated model:
├─ Previous error: -15%
├─ Model adjusted: Weights updated
├─ New prediction: 82 (more accurate for Monday)
└─ Actual: 80 (very close! 2% error) ✅

          ↓
CONTINUOUS IMPROVEMENT:
After 30 days:
├─ Accuracy improves from 85% → 88% → 91%
├─ Model learns unique patterns for this bakery
├─ Becomes more accurate over time
└─ System becomes more valuable  ✅
```

---

#### 📈 4.1.7 Feature Importance & Explainability

**Why prediction accuracy changes:**

```
FEATURE IMPORTANCE RANKING (Random Forest Output):

Importance | Feature               | Impact
-----------|----------------------|--------
   1.      | Day of Week          | 28% (most important)
   2.      | Weather              | 22%
   3.      | Historical Avg       | 18%
   4.      | Season               | 15%
   5.      | Holidays/Events      | 12%
   6.      | Day Trend            | 5%

INSIGHT FOR MANAGER:
"The day of week is your MOST important predictor.
 Fridays and Saturdays have 20%-40% higher demand than Mondays.
 So you should focus getting your predictions right for weekday/weekend."
```

---

### 📦 4.2 Inventory Management (SUPPORTING SYSTEM)

**Role:** Supports the prediction system by providing data and constraints.

Inventory is **NOT** the main focus, but it's **essential** for:
- Providing production constraints
- Tracking actual vs predicted
- Training data generation
- Feasibility checking

#### 4.2.1 Inventory Functions

```
PRIMARY ROLE: Supply Data to Prediction

1️⃣ CONSTRAINT CHECKING
   Before recommending production:
   ├─ Check ingredient availability
   ├─ Check storage/oven capacity
   └─ Adjust recommendation if needed

2️⃣ TRACKING ACTUAL vs PREDICTED
   Daily recording:
   ├─ Predicted demand vs Actual sales
   ├─ Production quantity vs Leftover
   └─ Helps model improve

3️⃣ INGREDIENT MANAGEMENT
   Track per category:
   ├─ Flour usage per bread type
   ├─ Butter consumption rate
   ├─ Other ingredients
   └─ Calculate exact requirements

4️⃣ DATA COLLECTION FOR ML
   End-of-day inventory data:
   ├─ Final sales count
   ├─ Leftover quantity
   ├─ Waste rate calculation
   └─ Feeds back to ML model
```

#### 4.2.2 Category-Level Tracking

**The system tracks EVERY bread type individually:**

```
🥐 CROISSANTS (Example)

Ingredients per unit:
├─ Flour: 80g
├─ Butter: 15g
├─ Sugar: 5g
└─ Yeast: 2g

Daily Tracking Example:
├─ Produced: 100 units
├─ Ingredients used: Flour 8kg, Butter 1.5kg, Sugar 0.5kg, Yeast 200g
├─ Sold: 85 units
├─ Leftover: 15 units
└─ Waste %: 15%

WEEKLY SUMMARY:
├─ Total produced (Mon-Sun): 700 units
├─ Total sold: 615 units
├─ Total wasted: 85 units
├─ Average waste rate: 12%
└─ Trend: Improving (last week was 14%)

CATEGORY INCLUDED:
├─ Croissants (regular)
├─ Sweet Bread (pain au chocolat, etc.)
├─ Loaves (baguette, ciabatta)
└─ Special Items (seasonal, custom orders)
```

---

### 🛒 4.3 POS Simulation System (SUPPORTING SYSTEM)

**Role:** Simulate realistic customer purchases for testing and ML training.

**Why Simulation?** Real POS integration is complex. Simulation allows:
- Testing the system in realistic conditions
- Generating sales data for model learning
- Demonstrating the system before production

#### 4.3.1 How POS Simulation Works

**Key Features: Weather-Based + Calendar-Based Realism**

The simulation uses the **same Weather API and Google Calendar API as the Prediction System** to generate realistic sales patterns based on actual weather and holidays.

```
DAILY SIMULATION PROCESS:

8:00 PM (System Initialization - The Reality Check):
   ├─ System reads today's predicted demand
   ├─ Fetches TODAY'S ACTUAL WEATHER from Weather API
   ├─ Calls Google Calendar API for "Today's" holiday status
   └─ Example: Predicted 100 croissants, Weather: Rainy, Holiday: Public Holiday

   ↓

8:05 PM (Weather & Holiday-Informed Simulation - The Planner vs Reality):
   Bakery opens at 6:00 AM, closes at 6:00 PM
   
   WEATHER & HOLIDAY ADJUSTMENTS:
   ├─ Today's weather: Rainy (-15% impact)
   ├─ Today's calendar status: PUBLIC HOLIDAY (+30% impact)
   ├─ Combined factor: (1 - 0.15) × (1 + 0.30) = 1.105 multiplier
   ├─ Adjusted base sales: 100 × 1.105 = 110.5 croissants
   └─ Use 110 or 111 as basis for simulated sales

   HOLIDAY EFFECT IN SIMULATION:
   ├─ Normal day: ~100 transactions
   ├─ Holiday detected: Generate 130-150 transactions (+30-50%)
   ├─ Higher customer volume throughout all time windows
   └─ Reflects real-world: More people shop on holidays
   
   MORNING (6 AM - 11 AM): 40% of adjusted demand
   ├─ Base: 110 × 40% = 44 croissants
   ├─ Holiday boost: Higher foot traffic from holiday shoppers
   ├─ Simulated: 48 croissants sold ✅ (exceeds expected due to holiday)
   └─ Inventory: 52 remaining
   
   AFTERNOON (11 AM - 3 PM): 35% of adjusted demand
   ├─ Base: 110 × 35% = 39 croissants
   ├─ Holiday effect: Many people shopping for holiday gatherings
   ├─ Weather effect: Rainy but holiday traffic overcomes it
   ├─ Simulated: 42 croissants sold (holiday > weather impact)
   └─ Inventory: 10 remaining
   
   EVENING (3 PM - 6 PM): 25% of adjusted demand
   ├─ Base: 110 × 25% = 27 croissants
   ├─ Holiday effect: Still strong, last-minute holiday purchases
   ├─ Simulated: 28 croissants sold
   └─ FINAL INVENTORY: -18 croissants ⚠️ (STOCK OUT!)

   ↓

RESULT RECORDED:
├─ Total Produced: 100
├─ Total Sold: 118 (EXCEED PRODUCTION due to holiday!)
├─ Total Leftover: 0 (ran out of stock)
├─ Stock-out event: 18 lost sales
├─ Waste Rate: 0% (but missed revenue opportunity)
├─ Weather Factor Applied: -15% (rainy)
├─ Holiday Factor Applied: +30% (public holiday)
├─ Combined Effect: Higher demand overcame weather impact ✅

   ↓

COMPARISON TO PREDICTION & LEARNING:
├─ Predicted (without holiday awareness): 85 croissants
├─ Predicted (with Calendar API): 110 croissants
├─ Simulated actual: 118 croissants (demand exceeded!)
├─ Error: +8 units (7% higher than holiday-adjusted prediction)
├─ Learning: Holiday effect is even stronger than expected
└─ Next holiday: Prediction will use refined weights ✅

THE PLANNER VS REALITY:
┌─────────────────────────────────────────────────────┐
│ PREDICTION ENGINE (The Planner):                    │
│ "Tomorrow is PUBLIC HOLIDAY + Friday + Sunny"       │
│ → Recommend producing 155 croissants               │
│                                                     │
│ POS SIMULATOR (The Reality):                        │
│ "Today IS public holiday, rainy weather"            │
│ → Generated 118 actual sales                        │
│ → Stock out! Demand exceeded recommendations        │
│                                                     │
│ VERDICT: Baker should have followed the prediction │
│         and produced even MORE! ✅                  │
└─────────────────────────────────────────────────────┘
```

**Why Calendar API Integration is Powerful:**

✅ **Prediction Improvement**: ML model knows exactly when holidays occur  
✅ **Realistic Simulation**: Customer behavior changes on holidays (verified by Calendar API)  
✅ **System Validation**: Prediction vs simulation reveals if model is accurate  
✅ **No Guessing**: Uses actual calendar data, not assumptions  
✅ **Prevents Stock-outs**: Shows consequences of underestimating holiday demand  
✅ **Learning Loop**: Each holiday refines future predictions

#### 4.3.2 Sales Distribution Pattern (THIS BAKERY)

This bakery has a unique customer pattern based on its location and type.

**Example: [YOUR BAKERY - Specify Location & Type]**

For this bakery, the system learns the specific sales distribution pattern:

```
THIS BAKERY'S PATTERN:
Based on: Location type, customer demographics, operating hours

Example Distribution (to be replaced with actual bakery's pattern):f
├─ Morning (6-11 AM): 40% of daily sales
│  └─ Primary customer segment: [e.g., office workers, school parents]
│
├─ Afternoon (11 AM-3 PM): 35% of daily sales
│  └─ Primary customer segment: [e.g., lunch break shoppers, delivery orders]
│
└─ Evening (3 PM-6 PM): 25% of daily sales
   └─ Primary customer segment: [e.g., after-work, dinner preparation]
```

**How Distribution is Used:**

When the system predicts 100 croissants for tomorrow:

```
STEP 1: Apply THIS bakery's distribution pattern
├─ Morning: 100 × 40% = 40 croissants
├─ Afternoon: 100 × 35% = 35 croissants
└─ Evening: 100 × 25% = 25 croissants

STEP 2: Add realistic variance (±10-15% per slot)
├─ Morning: 40 ± variance → simulated 35-45 units
├─ Afternoon: 35 ± variance → simulated 30-40 units
└─ Evening: 25 ± variance → simulated 21-29 units

STEP 3: Track throughout the day
├─ 11 AM: 40 croissants sold (on track)
├─ 3 PM: 35 sold so far (40 + whatever was sold in afternoon)
└─ 6 PM: Final count = total sold
```

**Learning & Improvement:**

As the system operates, it learns THIS bakery's actual pattern:

```
WEEK 1: System uses estimated distribution
└─ Based on location type (e.g., "office area")

WEEK 2-3: Collects actual sales data
├─ Records: What time customers buy?
├─ Pattern: Which slots are busier than expected?
└─ Adjusts: Distribution refined

WEEK 4+: Distribution becomes personalized
├─ System learns: "This bakery's morning peak is higher than typical"
├─ Pattern: "Fridays have 20% more afternoon sales"
├─ Result: Simulations become very accurate ✅
```

#### 4.3.3 Record Transactions

```
TRANSACTION RECORD (End of Day):

Total Produced: 100 croissants
Total Sold: 85 croissants
Leftover: 15 croissants

System records:
├─ Transaction timestamp
├─ Quantity sold
├─ Time of sale (morning/afternoon/evening slot)
├─ Product category
└─ Final inventory count
```

---

### ♻️ 4.4 Leftover Management & Donation (SIMPLE)

**Role:** Handle unavoidable leftover bread responsibly.

**Philosophy:** After prediction optimization, remaining waste → donate to charity  
**No discounting needed** - focus on social responsibility

#### 4.4.1 Donation Process

```
END OF DAY WORKFLOW:

6:00 PM (Bakery Closing Time):
   ├─ Check: How much unsold bread remains?
   ├─ Calculate: Leftover from today's production
   └─ Example: 15 croissants left unsold

   ↓

6:05 PM (Donation Action):
   ├─ Log: "15 croissants donated to City Charity X"
   ├─ Record: Charity name, donation time, quantity
   ├─ Update: "Leftover marked as donated"
   └─ Status: ✅ Waste prevented (not thrown away)

END-OF-DAY REPORT:
├─ Produced: 100   
├─ Sold: 85
├─ Donated: 15 ✅
└─ Waste Rate: 0% (prevented by prediction + donation)
```

#### 4.4.2 Donation Tracking

```
WEEKLY DONATION SUMMARY:

Bakery: "Sweet Bakery"
Week: Mar 15-21, 2026

Charity Partners:
├─ City Food Bank: 45 items (Mon, Wed, Thu)
├─ Homeless Shelter: 32 items (Tue, Fri)
└─ Community Kitchen: 28 items (Sat, Sun)

Total Donated: 105 items
Donation Rate: 15% of leftover
Social Impact: 105 meals provided to community ✅
```

---

### 🔗 4.5 Prediction + Inventory Integration (INTELLIGENT SYSTEM)

**This section explains how prediction and inventory work TOGETHER to create a smart system.**

#### 4.5.1 Real-World Scenario

```
🧠 SCENARIO: Friday Evening Prediction

STEP 1: PREDICTION RUNS (6:00 PM Thursday)

System analyzes:
├─ Tomorrow is Friday (demand +15%)
├─ Weather forecast: Sunny (+10%)
├─ No holidays or events
├─ Historical Friday average: 95 croissants
├─ Adjust for factors: 95 × 1.15 (Friday) × 1.10 (sunny) = 120

✅ PREDICTION: Friday demand = 120 croissants
```

```
STEP 2: INVENTORY CHECK (Still 6:00 PM Thursday)

System checks current supplies:
├─ Flour available: 30 kg ✓
│  └─ Needed for 120 croissants: 9.6 kg ✓
│
├─ Butter available: 4 kg ⚠️
│  └─ Needed for 120 croissants: 1.8 kg ✓
│
├─ Sugar available: 5 kg ✓
│  └─ Needed for 120 croissants: 0.6 kg ✓
│
└─ Yeast available: 200g ⚠️
   └─ Needed for 120 croissants: 240g ❌ INSUFFICIENT

CONSTRAINT DETECTED: Yeast insufficient!
```

```
STEP 3: INTELLIGENT ADJUSTMENT

Original prediction: 120 croissants
Available yeast: 200g (only 167 units worth)

System adjusts recommendation:
├─ Standard recommendation
│  ├─ Predicted: 120 croissants
│  ├─ Yeast needed: 240g
│  └─ Status: ❌ Not enough

└─ ADJUSTED recommendation:
   ├─ Produce: 100 croissants (fit within 200g yeast)
   ├─ Alternatively: Order more yeast tonight
   ├─ If ordered: Can still make 120
   └─ Manager chooses option
```

```
STEP 4: FINAL RECOMMENDATION TO MANAGER

┌──────────────────────────────────────────┐
│ 🧠 SMART PREDICTION + INVENTORY SYSTEM   │
├──────────────────────────────────────────┤
│                                          │
│ FRIDAY FORECAST:                         │
│ • Predicted Demand: 120 croissants       │
│ • Recommended Production: 100 croissants │
│                                          │
│ ⚠️ CONSTRAINT:                           │
│ • Yeast insufficient (need 240g, have   │
│   200g)                                  │
│                                          │
│ OPTIONS:                                 │
│ Option 1: Produce 100 (use available    │
│           inventory) ➜ May miss 20 sales│
│                                          │
│ Option 2: Order yeast tonight ➜ Produce│
│           120 as predicted ✅            │
│                                          │
│ RECOMMENDED: Option 2                    │
│ • Order yeast tonight (delivery morning) │
│ • Produce full 120 units                 │
│ • Trust the prediction                   │
│                                          │
└──────────────────────────────────────────┘
```

#### 4.5.2 Why This Integration Matters

```
WITHOUT INTEGRATION:
└─ Prediction says: Make 120 croissants
└─ Baker checks supplies: Only 200g yeast
└─ Baker guesses: "OK just make 100 instead"
└─ Result: Prediction wasted, opportunity lost

WITH INTELLIGENT INTEGRATION:
├─ Prediction + Inventory together analyze:
├─ "Demand is high, but ingredient X is limited"
├─ System suggests: "Order ingredient X"
├─ OR adjusts: "Make 100 now, then 20 more when supply arrives"
├─ Result: Smart constraint handling, maximum efficiency ✅
```

---

### 🔄 4.6 Bakery Manager Dashboard

**What the system shows the manager daily:**

```
DAILY DASHBOARD VIEW:

🌅 MORNING (Before production):
┌────────────────────────────────────────┐
│ TODAY'S PREDICTION & PLAN               │
├────────────────────────────────────────┤
│ Day: Friday, Sunny Weather             │
│                                        │
│ RECOMMENDED PRODUCTION:                │
│ • Croissants: 120 (high demand Friday) │
│ • Sweet Bread: 70                      │
│ • Loaves: 50                           │
│                                        │
│ INGREDIENT CHECKLIST:                  │
│ ✓ Flour: 35kg needed (have 38kg)      │
│ ✓ Butter: 8kg needed (have 8.5kg)     │
│ ✓ Sugar: 4kg needed (have 5kg)        │
│ ✓ Yeast: 450g needed (have 500g)      │
│                                        │
│ STATUS: ✅ All supplies ready          │
│                                        │
└────────────────────────────────────────┘

☀️ MIDDAY (Tracking actual sales):
┌────────────────────────────────────────┐
│ REAL-TIME SALES TRACKING               │
├────────────────────────────────────────┤
│ Time: 1:00 PM                          │
│                                        │
│ Item        │ Pred │ Sold │ Remaining │
│─────────────┼──────┼──────┼──────────│
│ Croissants  │ 120  │  78  │    42     │
│ Sweet Bread │  70  │  44  │    26     │
│ Loaves      │  50  │  32  │    18     │
│                                        │
│ Status: ✅ ON TRACK (63% sold by 1 PM)│
│         🟢 On pace to meet prediction  │
│                                        │
└────────────────────────────────────────┘

🌇 CLOSING (End of day summary):
┌────────────────────────────────────────┐
│ DAILY RESULTS                          │
├────────────────────────────────────────┤
│ CROISSANTS:                            │
│  Predicted: 120  Sold: 115  Waste: 5   │
│  Accuracy: 96% ✅ (Excellent)          │
│                                        │
│ SWEET BREAD:                           │
│  Predicted: 70   Sold: 68   Waste: 2   │
│  Accuracy: 97% ✅ (Excellent)          │
│                                        │
│ LOAVES:                                │
│  Predicted: 50   Sold: 48   Waste: 2   │
│  Accuracy: 96% ✅ (Excellent)          │
│                                        │
│ TOTAL WASTE: 9 units (2% waste rate)   │
│ TOTAL REVENUE: ✅ Optimized            │
│                                        │
│ 📊 Status: Excellent day! Orders being │
│    donated to City Food Bank.          │
│                                        │
│ 🤖 ML MODEL:                           │
│    Learning from today's data...       │
│    Accuracy trending: ↗️ Improving      │
│                                        │
└────────────────────────────────────────┘
```

---

## 🔄 5. Daily System Workflow

### 🌅 Morning (Before Production - 6:00 AM)

```
PREDICTION ENGINE RUNS:

1️⃣ System analyzes all factors:
   ├─ Historical sales data (past 30 days)
   ├─ Weather forecast for today
   ├─ Day of week (Mon/Tue/Wed/Thu/Fri/Sat/Sun)
   ├─ Any holidays or events
   └─ Current ingredient inventory

2️⃣ Machine Learning Model Predicts:
   ├─ Croissants: 120 units (confidence 88%)
   ├─ Sweet Bread: 70 units (confidence 92%)
   ├─ Loaves: 50 units (confidence 85%)
   └─ Ciabatta: 28 units (confidence 80%)

3️⃣ System Checks Constraints:
   ├─ Do we have enough ingredients?
   ├─ Do we have enough baking capacity?
   └─ Any adjustments needed?

4️⃣ Final Recommendation Delivered to Bakery:
   ✅ Produce: 120 croissants
   ✅ Produce: 70 sweet bread
   ✅ Produce: 50 loaves
   ✅ Produce: 28 ciabatta

   📋 Ingredient checklist provided
   ⏰ Ready for morning production!
```

---

### ☀️ Daytime (During Operating Hours)

```
POS SIMULATION RUNS:

Throughout the day:
├─ 6:00 AM - 11:00 AM: Morning sales simulated
├─ 11:00 AM - 3:00 PM: Afternoon sales simulated
└─ 3:00 PM - 6:00 PM: Evening sales simulated

System tracks:
├─ Total sold so far
├─ Remaining inventory
├─ % of daily prediction met
└─ Any anomalies detected

Real-time monitoring:
IF actual sales < 70% of prediction:
   └─ Alert manager: "Sales lower than expected"
   └─ Suggest: "May have excess at end of day"
```

---

### 🌇 Evening (End of Day - 6:00 PM)

```
END-OF-DAY RECORDING (AUTO-GENERATED FROM SIMULATION):

The system automatically compiles results from the entire day's 
POS simulation without manual input:

┌─────────────────────────────────────────┐
│ FINAL DAILY REPORT (System Generated)   │
├─────────────────────────────────────────┤
│                                         │
│ Total Produced Today: 268 units         │
│ (120 Croissants + 70 Sweet Bread        │
│  + 50 Loaves + 28 Ciabatta)             │
│                                         │
│ Total Sold Today: 250 units             │
│ (Aggregated from morning/afternoon/     │
│  evening simulation transactions)       │
│                                         │
│ Total Donated: 18 units                 │
│ └─ Charity: City Food Bank              │
│ └─ Waste prevented: ✅                  │
│                                         │
│ Waste Rate: 6.7%                        │
│                                         │
└─────────────────────────────────────────┘

AUTO-GENERATED DATA SOURCES:
├─ Morning simulation: X transactions recorded
├─ Afternoon simulation: Y transactions recorded
├─ Evening simulation: Z transactions recorded
├─ Total transactions: X + Y + Z = 250 units
└─ Leftover calculated: 268 - 250 = 18 units

DATA COLLECTED BY SYSTEM:
├─ Complete transaction log (with timestamps, quantities, weather, holiday status)
├─ Inventory levels at each time window
├─ Waste calculation per category
├─ All factors that affected sales (weather, holiday, time patterns)
└─ Confidence level: 100% (pure simulation, not estimated)

DONATION TRACKING:
├─ 18 units automatically marked for donation
├─ Charity: City Food Bank
├─ Time: 6:00 PM (at closing)
├─ Status: Recorded in database
└─ Social Impact: 18 meals provided ✅
```

---

### 🌙 Night (After Closing - After 6:00 PM)

```
ML MODEL LEARNING:

System compares:
├─ Predicted: 120 croissants
├─ Actual: 115 croissants (from today's simulation)
├─ Error: -5 units (4% error)

Model Updates:
├─ Analyzes: Why was prediction close?
├─ Factors today: Friday, sunny, no events
├─ Updates: Weights adjusted for Friday + sunny pattern
├─ Result: Tomorrow's prediction more accurate

Learning loop:
After 30 days → Model accuracy improves
After 90 days → Model becomes highly specialized to this bakery
After 1 year → Model achieves 92%+ accuracy ✅
```

---

## 🤖 6. Machine Learning Model

### Objective
**Predict next-day bread demand per category with high accuracy** to enable smart production decisions.

### Model Architecture

```
INPUT FEATURES (From Section 4.1.2)
├─ Historical Data
│  ├─ Past 30 days sales per category
│  ├─ Past production volumes
│  └─ Past leftover data
│
├─ Temporal Features
│  ├─ Day of week (1-7)
│  ├─ Month/Season
│  ├─ Holiday indicator
│  └─ Week number in year
│
├─ External Features  
│  ├─ Weather (sunny, rainy, etc.)
│  ├─ Temperature
│  ├─ Special events
│  └─ Local holidays
│
└─ Operational Features
   ├─ Current ingredient inventory
   ├─ Storage capacity availability
   ├─ Oven capacity
   └─ Staff availability
          ↓
    ┌─────────────────────────────┐
    │   RANDOM FOREST REGRESSION  │
    │   (Primary Model)           │
    │                             │
    │   OR                        │
    │                             │
    │   LINEAR REGRESSION         │
    │   (Baseline/Comparison)     │
    └─────────────────────────────┘
          ↓
OUTPUT: Predicted Demand Quantities
├─ Croissants: 115 units (confidence 88%)
├─ Sweet Bread: 68 units (confidence 91%)
├─ Loaves: 48 units (confidence 85%)
└─ Ciabatta: 30 units (confidence 80%)
```

### Continuous Improvement Loop

**The system gets SMARTER each day:**

```
DAY 1 - MORNING:
  System predicts 100 croissants
  
DAY 1 - EVENING:
  Actual sales: 85 croissants
  Error rate: 15%
  
DAY 1 - NIGHT:
  ML model analyzes anomaly
  → Was there rain? Yes (-15% factor applies)
  → Should have predicted 85, not 100
  → Update model weights
  
DAY 2 - MORNING:
  System predicts 82 croissants (adjusted for rainy day like yesterday)
  Actual: 80
  Error rate: 2.5% ✅
  
AFTER 30 DAYS:
  Accuracy: 85% → improves gradually
  
AFTER 90 DAYS:
  Accuracy: 91% → very good
  
AFTER 1 YEAR:
  Accuracy: 94%+ → specialized model for this bakery ✅
```

### Model Evaluation Metrics

```
MEASUREMENT CRITERIA:

1. Mean Absolute Error (MAE)
   └─ Average difference between predicted and actual
   └─ Example: MAE of 5 = average error of 5 units

2. Root Mean Square Error (RMSE)
   └─ Similar to MAE but penalizes large errors more
   └─ More useful when large errors are costly

3. Mean Absolute Percentage Error (MAPE)
   └─ Error as percentage of actual demand
   └─ Example: MAPE of 8% = 8% average error
   └─ **BEST FOR BUSINESS UNDERSTANDING**

4. R-squared (R²)
   └─ Measures how much variance is explained
   └─ Target: > 0.85 (85% of variance explained)

TARGET PERFORMANCE:
├─ MAPE < 10%  (less than 10% average error)
├─ R² > 0.85   (explains 85%+ of demand variance)
└─ Accuracy: > 90% after 3 months of operation
```

---

## 📊 7. Data Management

### Data Collection Points

```
DAILY DATA FLOWS:

🌅 MORNING: Production Plan
├─ Predicted demand per category
├─ Recommended production quantities
├─ Ingredient requirements
└─ Constraints detected

☀️ DAYTIME: Sales Data
├─ Simulated/actual sales per time slot
├─ Current inventory levels
├─ Any stock-outs or excess
└─ Customer behavior patterns

🌇 EVENING: Actual Results
├─ Total produced vs recommended
├─ Total sold vs predicted
├─ Total leftover
├─ Waste rate per category

🌙 NIGHT: Data Processing
├─ Error calculation (predicted vs actual)
├─ Model weight updates
├─ Feature importance calculation
└─ Preparation for next day
```

### Data Storage Structure

```
DATABASE SCHEMA (Per Day):

DATE: 2026-03-20

CATEGORY: Croissants
├─ Predicted: 120 units
├─ Recommended: 120 units
├─ Produced: 120 units
├─ Sold: 115 units
├─ Leftover: 5 units
├─ Waste Rate: 4%
└─ Weather: Sunny, 22°C

CATEGORY: Sweet Bread
├─ Predicted: 70 units
├─ Produced: 70 units
├─ Sold: 68 units
├─ Leftover: 2 units
├─ Waste Rate: 3%
└─ Note: No issues

CATEGORY: Loaves  
├─ Predicted: 50 units
├─ Produced: 50 units
├─ Sold: 48 units
├─ Leftover: 2 units
├─ Waste Rate: 4%
└─ Day of Week: Friday

DAILY SUMMARY:
├─ Total Waste: 9 units (2.5% waste rate)
├─ Overall Accuracy: 96% ✅
└─ Trend: Improving
```

---

## 🎯 8. Key Success Metrics

### System Performance Metrics

**Prediction Accuracy:**
- ✅ Target: MAPE < 10% (less than 10% average error)
- ✅ Target: R² > 0.85 (explains 85%+ of variance)
- ✅ Target: 90%+ prediction accuracy after 3 months

**Waste Reduction:**
- ✅ Target: 30-40% reduction in daily waste
- ✅ Target: Waste rate < 5% (vs industry 20-30%)
- ✅ Baseline: Typical bakery waste = 25-30%

**Ingredient Efficiency:**
- ✅ Reduce ingredient waste by 20-25%
- ✅ Optimize ordering to minimize spoilage
- ✅ Track usage per category

**System Reliability:**
- ✅ Daily operation: 99.5% uptime (bakery needs daily predictions)
- ✅ Data accuracy: 100% (auto-generated from simulation)
- ✅ Model performance: Improves continuously

### Business Impact

```
EXAMPLE: Month 1 vs Month 3

MONTH 1 (Starting):
├─ Waste rate: 28% (typical)
├─ Waste value: $400/week
├─ Prediction accuracy: 82%
└─ System learning phase

↓ (After 8-10 weeks of learning)

MONTH 3 (Optimized):
├─ Waste rate: 8% ✅ (70% reduction!)
├─ Waste value: $50/week ✅ ($350 savings)
├─ Prediction accuracy: 91%
└─ System fully optimized for this bakery

YEARLY IMPACT:
├─ Annual waste reduction: ~$18,000
├─ Environmental: 1,000+ kg less waste
├─ Revenue protection: Ingredients not overordered
└─ Reputation: "Smart, sustainable bakery"
```

---

## 🚀 9. Technical Stack (Recommended)

### System Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    MOBILE DASHBOARD                     │
│                       (Flutter)                         │
│              Lightweight, User-Friendly UI              │
└──────────────────────┬──────────────────────────────────┘
                       │
                       │ (Only talks to Node.js)
                       ↓
┌─────────────────────────────────────────────────────────┐
│                   NODE.JS MIDDLEWARE                    │
│            (API Gateway & Orchestration Layer)          │
│                                                         │
│  ✅ Security: Validates all requests                   │
│  ✅ Business Logic: Manages recipes, donations, etc    │
│  ✅ Orchestration: Coordinates multiple APIs           │
│  ✅ Automation: Schedules daily learning tasks         │
└──────┬────────────┬────────────┬────────────┬──────────┘
       │            │            │            │
       ↓            ↓            ↓            ↓
  ┌────────┐  ┌──────────┐  ┌────────┐  ┌─────────┐
  │Supabase│  │Python ML │  │Weather │  │Calendar │
  │Database│  │(FastAPI) │  │  API   │  │   API   │
  └────────┘  └──────────┘  └────────┘  └─────────┘
```

### Component Breakdown

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **Frontend** | Flutter  | Bakery manager dashboard - displays predictions, inventory, daily results |
| **API Gateway & Orchestration** | **Node.js (Express)** | **Core middleware - coordinates all system communication** |
| **ML Model** | Python (scikit-learn / RandomForest) | Demand prediction using historical data + weather + calendar |
| **ML Server** | Python (FastAPI) | REST API for prediction requests & model retraining |
| **Database** | **Supabase (PostgreSQL)** | **Secure, real-time database with authentication** |
| **Data Processing** | Pandas / NumPy | Data cleaning & feature engineering before ML |
| **Scheduling & Automation** | Node-cron | Automatic end-of-day reports & ML model retraining |
| **Weather API** | OpenWeatherMap API | Real-time weather data for prediction & simulation |
| **Calendar API** | Google Calendar API | Holiday/event detection for demand adjustment |
| **Visualization** | Matplotlib / Plotly | Analytics charts & performance dashboards |
| **Deployment** | AWS / Heroku | Production hosting for Node.js + Python services |

---

### 🔐 Why Node.js as Middleware? (Professional Justification)

#### 1️⃣ API Gateway Pattern (Security & Architecture)

**The Problem:**
```
❌ INSECURE: If a hacker decompiles your app, they find database credentials
   Mobile App → Direct Database Connection (EXPOSED!)
   └─ Anyone with credentials can access/modify data
```

**The Solution: Node.js Gatekeeper**
```
✅ SECURE: App only knows Node.js URL, not database credentials
   Mobile App → Node.js → Supabase
   
   Process:
   1. App sends: "Give me today's prediction"
   2. Node.js validates: "Is this user authorized?"
   3. Node.js checks: "What data can this user see?"
   4. Node.js queries: Supabase for safe data
   5. Node.js returns: Only necessary data to app
   
   Result: Database credentials protected, permissions enforced
```

**Why This Matters for Your Viva:**
> "I implemented a Node.js API Gateway to decouple the mobile application from the database. This ensures that database credentials are never exposed to the client, and all requests pass through centralized authentication and permission checks."

#### 2️⃣ Decoupling Business Logic (Maintainability & Scalability)

**The Problem:**
```
❌ BRITTLE: Business logic spread across multiple places
   - Recipe in database table
   - Donation rules in mobile app
   - Inventory calculations in Python
   
   If you change recipe: Update database + recompile app (users must update!)
```

**The Solution: Centralized Node.js Business Logic**
```
✅ MAINTAINABLE: All business rules in one place (Node.js)

EXAMPLES:

1. Recipe Changes
   BEFORE: Recipe change → Update database → Force app update
   AFTER: Recipe change → Update Node.js → All requests get new recipe instantly
   
2. Donation Rules
   Example: "Donate if leftover > 10 units"
   Change: "Donate if leftover > 15 units AND charity available"
   
   Implementation: Update Node.js rule
   Result: Next end-of-day report uses new rule automatically
   
3. Ingredient Constraints
   Example: "Max 80 croissants because butter limited to 5kg"
   If you get more butter: Update Node.js calculation
   Result: Tomorrow's recommendation will reflect new capacity
```

**Node.js Pseudo-Code Example:**
```javascript
// Centralized business logic in Node.js
function calculateMaxProduction(croissantRecipe) {
  const butterPerCroissant = 15; // grams
  const butterAvailable = 5000;  // grams (from Supabase inventory)
  
  return Math.floor(butterAvailable / butterPerCroissant);
  // Returns: 333 croissants max
}

// If butter supply changes, system automatically adapts
// No app update needed!
```

**Why This Matters for Your Viva:**
> "All bakery business logic is centralized in Node.js. Changes to recipes, donation rules, or inventory constraints only require a server update—no need to recompile or redistribute the mobile app."

#### 3️⃣ Efficient Orchestration (Non-blocking Asynchronous Coordination)

**The Problem:**
```
❌ SLOW: If Flutter app coordinates everything
   
   Timeline (Sequential):
   T=0s:   Call Weather API
   T=1s:   Wait for response
   T=2s:   Call Calendar API  
   T=3s:   Wait for response
   T=4s:   Send to Python ML
   T=5s:   Wait for ML result
   TOTAL: 5 seconds (user sees loading spinner) ❌
```

**The Solution: Node.js Asynchronous Orchestration**
```
✅ FAST: Node.js coordinates everything in parallel

Timeline (Asynchronous/Non-blocking):
T=0s:   Call Weather API AND Calendar API simultaneously (parallel)
T=1s:   Both APIs respond (while ML receives combined data)
T=1.5s: Python ML processes data
T=2s:   Complete. Result sent to app
TOTAL: 2 seconds (2.5x faster!) ✅

Code Example (Node.js):
const [weather, calendar] = await Promise.all([
  getWeather(),      // Non-blocking
  getCalendar()      // Non-blocking (parallel)
]);
const prediction = await sendToML({ weather, calendar });
```

**Why This Matters:**
- User sees fast response (2 seconds vs 5 seconds)
- System handles multiple bakeries simultaneously
- Scalable to thousands of requests

**Why This Matters for Your Viva:**
> "Node.js is designed for non-blocking I/O. While a traditional synchronous system would sequentially call the Weather API, Calendar API, and ML service, Node.js calls them in parallel. This ensures the mobile application remains responsive and the overall system is scalable."

#### 4️⃣ Handling the Learning Loop (Automated Scheduling & Retraining)

**The Problem:**
```
❌ MANUAL: Someone has to remember to retrain the ML model
   
   Monday: "Oops, forgot to retrain the model!"
   Tuesday: Using stale model
   Wednesday: Data accumulating but not feeding back
   Result: Model never improves ❌
```

**The Solution: Node.js Scheduled Automation (node-cron)**
```
✅ AUTOMATIC: Every night at 11:00 PM

Node.js Scheduler (Pseudo-code):
cron.schedule('0 23 * * *', async () => {
  // Every day at 11:00 PM:
  
  1. Compile end-of-day report
     ├─ Collect: All today's sales data
     ├─ Calculate: Waste rate, errors
     └─ Store: In Supabase
  
  2. Send to Python ML Server
     ├─ Message: "Retrain model with new data"
     └─ Wait: For Python to finish retraining
  
  3. Update model version
     ├─ Save: New trained model
     └─ Load: Into prediction system
  
  4. Test: New model on historical data
     ├─ Calculate: MAPE, R²
     └─ Verify: Performance acceptable
  
  5. Email to manager (optional)
     └─ "Yesterday's prediction accuracy: 94%"
});
```

**What This Enables:**
```
DAY 1-5: Model accuracy: 82% (learning phase)
DAY 6-10: Model accuracy: 87% (getting better)
DAY 11-30: Model accuracy: 91% (very good)
DAY 30+: Model accuracy: 95%+ (specialized to this bakery)

Why? Because Node.js retrained the model every single night!
```

**Why This Matters for Your Viva:**
> "I implemented automated model retraining using Node.js scheduling. Every night at 11 PM, the system collects the day's simulation data, sends it to the Python ML server for retraining, and updates the model. This ensures continuous improvement without manual intervention—demonstrating understanding of DevOps and automated ML pipelines."

---

### Why Supabase (Instead of Raw PostgreSQL)?

**Supabase = PostgreSQL + Security + Real-time + Authentication**

```
BENEFITS:

✅ Real-time Database
   └─ If prediction changes, dashboard updates instantly
   
✅ Built-in Authentication
   └─ User login/logout handled by Supabase
   └─ Bakery can have multiple staff members
   
✅ Row-Level Security (RLS)
   └─ Each bakery sees only its own data
   └─ Prevents data leaks between bakeries
   
✅ PostgreSQL Power
   └─ Relational data (bakeries, predictions, sales, inventory)
   └─ Complex queries for analytics
   
✅ REST API
   └─ Node.js can query easily via: supabase.from('sales').select()
   
✅ Backup & Scaling
   └─ Automatic backups
   └─ Can scale to multiple bakeries later
```

**Example Row-Level Security (Prevents Data Leaks):**
```sql
-- Supabase RLS Policy
CREATE POLICY "Bakeries can only see their own data"
ON sales
FOR SELECT
USING (bakery_id = auth.uid());

-- Result: Bakery A cannot access Bakery B's sales data
--         Even if they try to query directly!
```

---

## 💬 10. Design Philosophy & Lecturer Explanation

### Core Design Principle

**"The system is built on PREDICTION as the main pillar. Everything else (inventory, POS, donation) supports the prediction engine to continuously improve its accuracy."**

### Why Prediction is the Core Module

```
TRADITIONAL APPROACH (Discounting):
└─ Predict demand poorly
└─ Produce too much
└─ Put items on sale
└─ Hope someone buys
└─ Still waste food
└─ Reactive, not proactive ❌

SMART APPROACH (Prediction): ⭐ OUR SYSTEM
├─ Predict demand accurately
├─ Produce exactly right amount
├─ Minimal waste from start
├─ Use inventory to refine predictions
├─ Donation handles unavoidable waste
├─ Proactive, intelligent, sustainable ✅
```

### Key Design Decisions

**1. Focus on ONE Bakery (Not Multiple)**
- ✅ **Realistic:** One location makes the system implementable
- ✅ **Specialized:** ML model learns bakery-specific patterns
- ✅ **Practical:** Can be expanded to multiple bakeries as Phase 2
- 📊 **Data Quality:** Concentrate on depth, not breadth

**2. Predictions with Detailed Input Features**
- ✅ **Historical Data:** Past 30 days sales per category
- ✅ **Time Features:** Day of week, seasonality, holidays
- ✅ **External Factors:** Weather, local events, public holidays
- ✅ **Operational Data:** Ingredient levels, capacity constraints
- 🧠 **Intelligent:** System knows weather affects croissants differently than loaves

**3. Inventory as Support (Not Main Goal)**
- ✅ **Real Purpose:** Provides training data, tracks accuracy
- ✅ **Constraints:** Limits maximum production
- ✅ **Feedback Loop:** Actual vs predicted improves model
- 📦 **Not Storage Focus:** Inventory is tool, not destination

**4. POS Simulation**
- ✅ **Testing:** Simulates today's sales patterns realistically
- ✅ **Learning:** Generates data for model training
- ✅ **Practical:** No need to integrate real POS systems
- ⏱️ **Demo Ready:** Works immediately for presentations

**5. Donation for Leftover**
- ✅ **Sustainable:** Social responsibility, not waste
- ✅ **Simple:** No discounting complexity
- ✅ **Realistic:** Real bakeries donate unsold inventory
- 💚 **Values:** Focuses on community impact

### Impressive Features to Highlight to Lecturer

✨ **These show sophisticated thinking:**

1. **Detailed Input Features** (Section 4.1.2)  
   → Shows you understand demand drivers
   → Categories A-D breakdown = professional system design

2. **Prediction + Inventory Integration** (Section 4.5)  
   → Not just predicting, but handling real constraints intelligently
   → "System adjusts recommendation when yeast insufficient" = problem solving

3. **Continuous Learning Loop** (Section 6)  
   → System improves accuracy from 82% → 91% over time
   → Shows ML fundamentals: predict → compare → learn → improve

4. **Category-Level Tracking** (Section 4.2.2)  
   → Not just "total waste" but granular per bread type
   → Tracks flour, butter, sugar per unit = ingredient optimization

5. **Feature Importance Analysis** (Section 6)  
   → Shows which factors matter most
   → "Day of week = 28% importance" = data-driven insights

### How to Present to Your Lecturer

```
"Thank you for your guidance. We've redesigned the system 
based on your feedback:

1. PREDICTION IS NOW THE STAR ⭐
   └─ All other modules support accurate prediction

2. FOCUS ON ONE BAKERY
   └─ Realistic, manageable, allows deep specialization

3. DETAILED PREDICTION INPUTS
   └─ Historical data + weather + time features + operational constraints
   └─ System considers if it's Friday + sunny + inventory limited

4. INTELLIGENT INTEGRATION
   └─ Not just predicting, but handling real-world constraints
   └─ "Predicted 120 but yeast limited? Adjust to 100" example

5. DONATION FOR SOCIAL IMPACT
   └─ Unavoidable waste goes to charity
   └─ No discounting complexity, focus on waste prevention

6. CONTINUOUS LEARNING
   └─ System improves accuracy from 82% → 91% after 3 months
   └─ Each day's actual data refines tomorrow's prediction

This makes the system:
✅ Technically sound (ML + data science)
✅ Socially responsible (donation focus)
✅ Practically implementable (one bakery, realistic scope)
✅ Educationally valuable (shows prediction, inventory, and learning)
```

---

**Document Version:** 2.0 (Restructured)  
**Last Updated:** April 2026  
**Status:** ✅ Ready for Supervisor Review & Implementation

---

## 📋 Implementation Checklist

### Phase 1: Core Prediction Engine (Weeks 1-4)
- [ ] Design database schema for historical data
- [ ] Build data collection dashboard (admin input)
- [ ] Implement Random Forest model for demand prediction
- [ ] Create model evaluation metrics (MAPE, R²)
- [ ] Test with simulated 30 days of data

### Phase 2: Inventory & Integration (Weeks 4-6)
- [ ] Build inventory tracking system (per category, per ingredient)
- [ ] Integrate inventory constraints with predictions
- [ ] Create smart recommendation logic (adjust if ingredients limited)
- [ ] Build manager dashboard (shows predictions + constraints)

### Phase 3: POS Simulation (Weeks 6-7)
- [ ] Implement sales distribution profiles (Morning/Balanced/Evening)
- [ ] Build simulated transaction system
- [ ] Create real-time sales tracking
- [ ] Test simulation accuracy

### Phase 4: Donation & End-of-Day (Week 8)
- [ ] Build end-of-day reporting system
- [ ] Implement donation tracking
- [ ] Create learning loop (ML model updates)
- [ ] Build performance analytics dashboard

### Phase 5: Testing & Refinement (Week 9)
- [ ] System testing with realistic scenarios
- [ ] Accuracy evaluation (target: >90% MAPE)
- [ ] Documentation completion
- [ ] Presentation preparation

---

## 📚 Document Map

| Section | Focus | Key Points |
|---------|-------|-----------|
| 1. Introduction | System Overview | Single bakery, prediction-focused, components |
| 2. Problem Statement | Why It Matters | Waste challenge, real examples, consequences |
| 3. Proposed Solution | The Approach | Two-part strategy: prevention + recovery |
| **4. System Architecture** | **MAIN CONTENT** | **Detailed breakdown of all components** |
| 4.1 Prediction (CORE) | Detailed Prediction | Input features (4 categories), output, learning loop |
| 4.2 Inventory (SUPPORT) | Inventory System | Constraints, tracking, feasibility checking |
| 4.3 POS Simulation | Sales Generator | Distribution profiles, transaction recording |
| 4.4 Donation | Waste Recovery | Charity partners, tracking, social impact |
| 4.5 Integration | Intelligent System | How prediction + inventory solve together |
| 4.6 Dashboard | Manager View | Daily displays (morning/midday/evening) |
| 5. Daily Workflow | Operations | Step-by-step: morning → night → learning |
| 6. ML Model | Prediction Engine | Architecture, metrics, continuous improvement |
| 7. Data Management | Data Flow | Collection, confidence levels, storage |
| 8. Success Metrics | Evaluation | Performance targets, business impact examples |
| 9. Technical Stack | Implementation | Technology choices & justification |
| 10. Design Philosophy | Lecturer Info | Design principles, features to highlight |

---

## 🎯 Quick Summary for Your Lecturer

### The New System Focus

✅ **BEFORE:** "Multiple bakeries, mobile marketplace, dynamic discounting"  
✅ **AFTER:** "ONE bakery, intelligent demand PREDICTION, realistic operations"

### What Changed (Teacher's Feedback Applied)

1. **Prediction is now MAIN FEATURE**
   - Moved to section 4.1 (core module)
   - Expanded with detailed input features (4 categories)
   - Shows continuous learning loop

2. **ONE BAKERY FOCUS**
   - Realistic implementation
   - Manageable data
   - Possible to specialize and improve

3. **DETAILED PREDICTION INPUTS**
   - Category A: Historical data (past 30 days)
   - Category B: Time features (day, seasonality)
   - Category C: External factors (weather, events)
   - Category D: Operational data (inventory, capacity)

4. **INVENTORY AS SUPPORT**
   - Provides constraints (can't make more than ingredients allow)
   - Tracks actual vs predicted (improves model)
   - Enables feasibility checking

5. **POS IS SIMPLE**
   - Just simulates sales throughout day
   - Generates data for learning
   - Not a main feature

6. **DONATION SIMPLE & MEANINGFUL**
   - No discounting complexity
   - Handles unavoidable waste with charity partners
   - Tracks social impact

7. **SMART INTEGRATION**
   - Prediction + Inventory = intelligent recommendations
   - "Yeast limited? Adjust production down" example
   - Real-world problem solving

### Where to Find What

📊 **For Prediction Details:** Section 4.1.2 (Input Features)  
📦 **For Inventory Details:** Section 4.2 (Supporting System)  
🛒 **For POS Details:** Section 4.3 (Simple Simulation)  
♻️ **For Donation Details:** Section 4.4 (Page has one donation example)  
🔗 **For Integration Examples:** Section 4.5 (Prediction + Inventory together)  
🧠 **For ML Details:** Section 6 (Model architecture & learning)  

---

## ✨ Why Your Lecturer Will Like This

✅ **Academic Rigor**  
- ML model with continuous learning  
- Feature importance analysis  
- MAPE and R² evaluation metrics  

✅ **Practical Implementation**  
- Single bakery (realistic scope)  
- Real-world constraints (limited ingredients, oven capacity)  
- Actual business logic  

✅ **Social Responsibility**  
- Donation focus (not just profit)  
- Waste prevention (primary) over recovery (secondary)  
- Community impact tracking  

✅ **Systems Thinking**  
- All components support prediction accuracy  
- Feedback loops (actual data → model learning)  
- Constraints and intelligent adjustments  

✅ **Clear Presentation**  
- One core objective (minimize waste via prediction)  
- Supporting modules clearly defined  
- Real examples throughout
