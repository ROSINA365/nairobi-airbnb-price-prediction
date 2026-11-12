
# Predicting Airbnb Prices in Nairobi, Kenya (SAS)

Predicting the nightly price of Airbnb listings in Nairobi with **LASSO regression, a decision tree and a random forest**, built end to end in **SAS**.

**Tools:** SAS Studio (SAS OnDemand for Academics) · PROC GLMSELECT · PROC HPSPLIT · PROC HPFOREST · PROC SQL · PROC UNIVARIATE · PROC SGPLOT
**Data:** [Inside Airbnb](https://insideairbnb.com/get-the-data/) – Nairobi detailed listings, collected 14 September 2026 (22,669 listings, 90 variables, prices in Kenyan Shillings)

---

## Key Results

| Model | Test RMSE (log price) | Typical error (KES) | Variance explained (test) | Train-to-test gap |
|---|---|---|---|---|
| LASSO regression | 0.4335 | 3,882 | 56% | 1.6% |
| Decision tree | 0.3973 | 3,566 | 63% | 7.9% |
| **Random forest** | **0.3715** | **3,328** | **68%** | OOB RMSE 0.3647 |

- The **random forest was the most accurate model**. Its test error was **14.3% lower than LASSO** and 6.5% lower than the decision tree.
- All three models agree that **size** (bedrooms, bathrooms, guests) and **location** are the main drivers of price.
- Listings in **Westlands are about 48% more expensive** than similar listings in South-West Nairobi. Listings in **Kilimani are about 24% more expensive**. Listings in the East, North and CBD are 22–31% cheaper.
- Availability, review counts, minimum nights and superhost status have **little effect** on price.

![RMSE comparison](images/rmse_comparison.png)

---

## Business Question

What drives the nightly price of an Airbnb listing in Nairobi, and how accurately can we predict a fair price for a new listing?

A model like this could help:

- **New hosts** set a starting price.
- **Platforms** flag listings that are priced far above or below similar homes.
- **Investors** see which areas and property sizes earn the most per night.

---

## Project Workflow

### 1. Data import and cleaning

- Some listings had line breaks inside a host description field, so one listing was split across several rows. A DATA step removed line breaks inside quoted text before import. This kept all **22,669 listings** intact.
- Converted `price` from text (`"$7,640.00"`) to a number.
- Removed **386 listings with no price** (1.7%).
- Found outliers with the **1.5 × IQR rule on log(price)**. Applying the rule to raw prices would have flagged normal large homes. This removed **295 listings**, including a one-bedroom apartment listed at KES 4.17 million per night.
- Final clean data: **21,988 listings** (97% of the original), with prices from KES 1,036 to KES 35,797.

### 2. Transforming the target

Price was strongly right-skewed (skewness 2.05). I compared square root and natural log transformations:

| Variable | Skewness | Kurtosis |
|---|---|---|
| price | 2.052 | 5.338 |
| √price | 1.056 | 1.278 |
| **log(price)** | **0.203** | **−0.361** |

I used **log(price)** as the dependent variable for all models.

| Before (price) | After (log price) |
|---|---|
| ![Price histogram](images/price_histogram_raw.png) | ![Log price histogram](images/log_price_histogram.png) |

### 3. Preparing the predictors

**Multicollinearity.** I used a correlation heat map and VIFs:

- `availability_60` had a VIF of 54.6 and `availability_90` had a VIF of 28.6. I removed both and kept `availability_30`.
- I removed six review sub-scores and kept the overall rating.
- After these changes, every VIF was **below 4**.

![Correlation heat map](images/correlation_heatmap.png)

**Too many categories.** I grouped:

- `property_type` from 69 levels to 4.
- 17 neighbourhoods into 6 areas, based on location in Nairobi.
- `room_type` from 4 levels to 3.

**Missing values:**

- All 12,700 listings with a missing review score were exactly the listings with **zero reviews**. I set `reviews_per_month` to 0 for these listings. I turned the rating into a grouped variable with "No reviews" as its own group, so no listings were dropped.
- I filled small gaps (under 2%) in bedrooms, beds, bathrooms and nights with the median.

**Feature engineering:**

- Applied `log(x + 1)` to bedrooms, beds and bathrooms. This brought their skewness down from about 15 to under 2.
- Added squared terms for guest capacity, latitude and longitude, because their relationships with price are curved.
- Standardized all numeric predictors (z-scores).
- These steps raised R² for the numeric predictors **from 39.6% to 48.3%**.

![Log price vs latitude](images/log_price_vs_latitude.png)

**Train/test split.** I used an 80/20 random split with PROC SURVEYSELECT and a fixed seed, giving **17,591 training** and **4,397 testing** listings. I checked that both samples had the same price distribution and the same mix of room types and areas.

### 4. Models

**LASSO regression (PROC GLMSELECT)**

- Chose the model with 10-fold cross-validation.
- Kept 28 effects. It dropped five weak candidates, mostly availability and review-count variables.
- R² = 0.565, with almost no overfitting (test error only 1.6% above train).

![LASSO coefficient progression](images/lasso_coefficient_progression.png)

**Decision tree (PROC HPSPLIT)**

- Pruned from 669 to 153 leaves with cost-complexity pruning and 10-fold cross-validation.
- The first split is **bedrooms**, then **area**, then longitude or guest capacity.
- I scored the test data with the tree's saved SAS scoring code.

![Decision tree top levels](images/decision_tree_top_levels.png)

**Random forest (PROC HPFOREST)**

- Grew 200 trees, trying 7 variables at each split.
- The out-of-bag error leveled off after about 100 trees.
- The most important predictors were bedrooms, area, bathrooms, longitude, guest capacity and latitude.

![Random forest variable importance](images/random_forest_variable_importance.png)

---

## Recommendations

- **To predict prices** (for example, a pricing tool for new hosts), use the **random forest**. It is the most accurate on new listings.
- **To explain prices** (for example, how much more a Westlands listing or an extra bedroom earns), use the **LASSO model**. Its coefficients can be read directly.
- **To give simple rules** to non-technical hosts, use the **top levels of the decision tree**.
- **For hosts:** location and size set most of the price. Ratings of 4.8 and above are linked to higher prices.

## Limitations and Next Steps

- The models explain 56–68% of price variation. The rest depends on things not in the data, such as interior quality, amenities, views and the host's pricing strategy. **Next step:** add amenity flags and the distance to the CBD, the airport and major malls.
- The data shows asking prices on a single date, not booked prices, so it does not capture seasonal changes.
- The models apply to listings priced between KES 917 and KES 35,838. They should not be used for luxury listings above this range.
- Further work: tune the random forest, and try gradient boosting.

---

## Repository Structure

```
├── README.md
├── Nairobi_Airbnb_Data_Analysis.sas   # Full SAS program: cleaning → features → 3 models → comparison
├── report/
│   └── Predicting_Airbnb_Prices_in_Nairobi.docx   # Full write-up with all SAS output
└── images/                             # Key figures used in this README
```

## How to Run

1. Download `listings.csv.gz` for Nairobi from [Inside Airbnb](https://insideairbnb.com/get-the-data/) and extract `listings.csv`.
2. Upload it to a folder in SAS Studio (SAS OnDemand for Academics is free).
3. Change the `%let path = ...;` line at the top of the `.sas` file to point to your folder.
4. Run the program from top to bottom. The models use fixed seeds (`seed=12345`), so the results can be reproduced.

> The raw data is not included in this repository. Inside Airbnb data is shared under a Creative Commons Attribution 4.0 license and can be downloaded from the link above.

---

**Author:** Sharon Rosina Wamalwa – MS Business Analytics, University of South Dakota (May 2027)
Project for DSCI 519 – Advanced Business Analytics
[LinkedIn](https://www.linkedin.com/in/YOUR-PROFILE) · [Portfolio](https://github.com/YOUR-USERNAME)
