/*****************************************************
 Airbnb Data Analysis Term Project - Nairobi, Kenya
 Sharon Rosina Wamalwa
*****************************************************/

/* Set the project folder and a permanent library */
%let path = ~/DSCI 519/AssignmentsFall2026;
libname airbnb "&path";

/* Remove line breaks inside quoted text fields so each listing is one row */
data _null_;
    infile "&path/listings.csv" recfm=n;
    file "&path/listings_clean.csv" recfm=n;
    retain inquote 0;
    input c $char1.;
    if c = '"' then inquote = 1 - inquote;
    if inquote = 1 and c in ('0A'x, '0D'x) then c = ' ';
    put c $char1.;
run;

/* Import the cleaned CSV file */
proc import datafile="&path/listings_clean.csv"
    out=airbnb.listings
    dbms=csv
    replace;
    getnames=yes;
    datarow=2;
    guessingrows=max;
run;

/* Check the imported data set */
proc contents data=airbnb.listings varnum;
run;

/* View the first 5 listings for key variables */
proc print data=airbnb.listings(obs=5);
    var id name neighbourhood_cleansed room_type accommodates bedrooms price;
run;


/*****************************************************
 Step 2a (i): Investigate the dependent variable (price)
 Missing and nonsensical values - PROC UNIVARIATE
*****************************************************/

/* Convert price from text ( $7,640.00) to a numeric variable */
data airbnb.nairobi;
    set airbnb.listings;
    /* Remove the $ sign and commas, then read the value as a number */
    price_num = input(compress(price, '$,'), best32.);
    /* Keep the original text price under a new name and use price as the numeric version */
    drop price;
    rename price_num = price;
    label price_num = "Nightly price (KES)";
run;

/* Count missing and non-missing price values */
proc means data=airbnb.nairobi n nmiss min max mean median;
    var price;
    title "Step 2a (i): Missing values and range of price";
run;

/* Count listings with a zero or negative price (nonsensical values) */
proc sql;
    title "Step 2a (i): Listings with a price of zero or less";
    select count(*) as zero_or_negative_price
    from airbnb.nairobi
    where price <= 0 and price is not missing;
quit;

/* Distribution, range and extreme values of price */
proc univariate data=airbnb.nairobi nextrobs=10;
    var price;
    histogram price / normal;
    inset n mean median std skewness kurtosis min max / position=ne;
    title "Step 2a (i): Distribution of price (PROC UNIVARIATE)";
run;
title;



/*****************************************************
 Step 2a (ii): Identify and remove outliers in price
*****************************************************/

/* Create log of price for listings that have a price */
data work.price_log;
    set airbnb.nairobi;
    where price ne .;
    log_price = log(price);
run;

/* Box plot of log price to show outliers visually */
proc sgplot data=work.price_log;
    vbox log_price;
    yaxis label="Log of nightly price (KES)";
    title "Step 2a (ii): Box plot of log(price)";
run;

/* Get Q1, Q3 and IQR of log price */
proc univariate data=work.price_log noprint;
    var log_price;
    output out=work.fences q1=q1 q3=q3 qrange=iqr;
run;

/* Calculate the lower and upper outlier cut-offs and convert them back to KES */
data work.fences;
    set work.fences;
    lower_log = q1 - 1.5*iqr;
    upper_log = q3 + 1.5*iqr;
    lower_kes = exp(lower_log);
    upper_kes = exp(upper_log);
run;

/* Show the outlier cut-offs */
proc print data=work.fences noobs;
    var q1 q3 iqr lower_log upper_log lower_kes upper_kes;
    format lower_kes upper_kes comma12.2;
    title "Step 2a (ii): Outlier cut-offs (1.5 x IQR rule on log price)";
run;

/* Split listings into a clean data set and an outlier data set; drop missing prices */
data airbnb.nairobi_clean work.price_outliers;
    if _n_ = 1 then set work.fences(keep=lower_kes upper_kes);
    set airbnb.nairobi;
    if missing(price) then delete;
    if price < lower_kes or price > upper_kes then output work.price_outliers;
    else output airbnb.nairobi_clean;
    drop lower_kes upper_kes;
run;

/* Count low and high outliers */
proc sql;
    title "Step 2a (ii): Number of low and high price outliers";
    select sum(price < 1000) as low_outliers,
           sum(price >= 1000) as high_outliers,
           count(*) as total_outliers
    from work.price_outliers;
quit;

/* List the 10 highest-priced outliers */
proc sort data=work.price_outliers;
    by descending price;
run;

proc print data=work.price_outliers(obs=10) noobs;
    var id name room_type accommodates bedrooms price;
    format price comma12.2;
    title "Step 2a (ii): Ten highest-priced outlier listings";
run;

/* Check price in the clean data set after removing missing values and outliers */
proc means data=airbnb.nairobi_clean n nmiss min max mean median;
    var price;
    title "Step 2a (ii): Price after removing missing values and outliers";
run;
title;



/*****************************************************
 Step 2a (iii) and (iv): Shape of the price distribution
 and choice of transformation
*****************************************************/

/* Distribution of price after removing missing values and outliers */
proc univariate data=airbnb.nairobi_clean normal;
    var price;
    histogram price / normal;
    qqplot price / normal(mu=est sigma=est);
    inset n mean median std skewness kurtosis / position=ne;
    title "Step 2a (iii): Distribution of price (clean data)";
run;

/* Add square root and natural log versions of price to the clean data */
data airbnb.nairobi_clean;
    set airbnb.nairobi_clean;
    sqrt_price = sqrt(price);
    log_price  = log(price);
    label sqrt_price = "Square root of price"
          log_price  = "Natural log of price";
run;

/* Compare skewness and kurtosis of price and its transformations */
proc means data=airbnb.nairobi_clean n mean median skewness kurtosis maxdec=3;
    var price sqrt_price log_price;
    title "Step 2a (iv): Skewness and kurtosis of price and its transformations";
run;

/* Distribution of log price */
proc univariate data=airbnb.nairobi_clean normal;
    var log_price;
    histogram log_price / normal;
    qqplot log_price / normal(mu=est sigma=est);
    inset n mean median std skewness kurtosis / position=ne;
    title "Step 2a (iv): Distribution of log(price)";
run;
title;






/*****************************************************
 Step 2b (i) 1: Multicollinearity among numeric predictors
*****************************************************/

/* Convert bathrooms_text (e.g. "1.5 baths", "1 shared bath", "Half-bath") to numbers */
data airbnb.nairobi_clean;
    set airbnb.nairobi_clean;
    /* Half-baths count as 0.5; otherwise take the number at the start of the text */
    if index(lowcase(bathrooms_text), 'half-bath') > 0 then bathrooms_num = 0.5;
    else bathrooms_num = input(scan(bathrooms_text, 1, ' '), ?? best12.);
    /* Flag shared bathrooms: 1 = shared, 0 = private, missing if no bathroom information */
    if missing(bathrooms_text) then shared_bath = .;
    else shared_bath = (index(lowcase(bathrooms_text), 'shared') > 0);
    /* Replace the empty bathrooms column with the numeric version */
    drop bathrooms;
    rename bathrooms_num = bathrooms;
    label bathrooms_num = "Number of bathrooms"
          shared_bath   = "Shared bathroom (1 = yes)";
run;

/* List of numeric predictors from the data dictionary */
%let numvars = accommodates bedrooms beds bathrooms latitude longitude
               minimum_nights maximum_nights
               availability_30 availability_60 availability_90 availability_365
               number_of_reviews number_of_reviews_ltm number_of_reviews_l30d
               review_scores_rating review_scores_accuracy review_scores_cleanliness
               review_scores_checkin review_scores_communication
               review_scores_location review_scores_value reviews_per_month;

/* Correlation matrix of the numeric predictors saved to a data set */
proc corr data=airbnb.nairobi_clean noprint outp=work.corr_out;
    var &numvars;
run;

/* Reshape the correlation matrix into one row per pair of variables */
data work.corr_long;
    set work.corr_out(where=(_type_ = 'CORR'));
    array v{*} &numvars;
    length var2 $32;
    row = _n_;
    do col = 1 to dim(v);
        var2 = vname(v{col});
        r = v{col};
        output;
    end;
    keep _name_ var2 r row col;
run;

/* Heat map of correlations between numeric predictors */
ods graphics / width=9in height=8in;
proc sgplot data=work.corr_long;
    heatmapparm x=_name_ y=var2 colorresponse=r / colormodel=(blue white red);
    xaxis display=(nolabel) fitpolicy=rotate;
    yaxis display=(nolabel) reverse;
    gradlegend / title="Correlation (r)";
    title "Step 2b (i): Correlation heat map of numeric predictors";
run;
ods graphics / reset;

/* List only the pairs with a strong correlation (|r| >= 0.70) */
proc sort data=work.corr_long(where=(col > row and abs(r) >= 0.70)) out=work.high_corr;
    by descending r;
run;

proc print data=work.high_corr noobs label;
    var _name_ var2 r;
    format r 6.3;
    label _name_ = "Variable 1" var2 = "Variable 2" r = "Correlation (r)";
    title "Step 2b (i): Pairs of numeric predictors with |r| >= 0.70";
run;

/* Regression with Variance Inflation Factors (VIF) - all numeric predictors */
proc reg data=airbnb.nairobi_clean;
    model log_price = &numvars / vif;
    ods select NObs ParameterEstimates;
    title "Step 2b (i): VIF check - all numeric predictors";
run;
quit;

/* Regression with VIF after removing availability_60, availability_90 and six review sub-scores */
%let numvars_reduced = accommodates bedrooms beds bathrooms latitude longitude
                       minimum_nights maximum_nights availability_30 availability_365
                       number_of_reviews number_of_reviews_ltm number_of_reviews_l30d
                       review_scores_rating reviews_per_month;

proc reg data=airbnb.nairobi_clean;
    model log_price = &numvars_reduced / vif;
    ods select NObs ParameterEstimates;
    title "Step 2b (i): VIF check - after removing highly correlated predictors";
run;
quit;
title;



/*****************************************************
 Step 2b (i) 2: Categorization - collapse categorical
 variables with many levels
*****************************************************/

/* Frequency tables of categorical variables before collapsing */
proc freq data=airbnb.nairobi_clean order=freq;
    tables property_type neighbourhood_cleansed room_type host_is_superhost / nocum;
    title "Step 2b (i) 2: Categorical variables before collapsing";
run;

/* Collapse property_type, neighbourhood_cleansed and room_type into fewer groups */
data airbnb.nairobi_clean;
    set airbnb.nairobi_clean;
    length property_group $26 area $10 room_group $17;
    pt = lowcase(property_type);

    /* Property type grouped by type of building */
    if index(pt, 'rental unit') > 0 then property_group = 'Rental unit';
    else if index(pt, 'condo') > 0 or index(pt, 'serviced apartment') > 0
         or index(pt, 'loft') > 0 then property_group = 'Condo/serviced apartment';
    else if index(pt, 'hotel') > 0 or index(pt, 'bed and breakfast') > 0
         or index(pt, 'pension') > 0 or index(pt, 'resort') > 0
         or index(pt, 'casa particular') > 0 then property_group = 'Hotel/B&B';
    else property_group = 'House and other';

    /* Neighbourhood grouped by location in Nairobi */
    select (neighbourhood_cleansed);
        when ('Kilimani')                         area = 'Kilimani';
        when ('Westlands')                        area = 'Westlands';
        when ('Kibra', 'Langata', 'Dagoretti')    area = 'South-West';
        when ('Starehe', 'Kamukunji')             area = 'CBD';
        when ('Roysambu', 'Kasarani', 'Ruaraka', 'Mathare') area = 'North';
        otherwise                                 area = 'East';
    end;

    /* Room type with hotel and shared rooms combined */
    if room_type in ('Hotel room', 'Shared room') then room_group = 'Hotel/shared room';
    else room_group = room_type;

    drop pt;
    label property_group = "Property type (grouped)"
          area           = "Area of Nairobi (grouped)"
          room_group     = "Room type (grouped)";
run;

/* Check that every original neighbourhood went into the right area */
proc freq data=airbnb.nairobi_clean;
    tables neighbourhood_cleansed * area / nopercent norow nocol;
    title "Step 2b (i) 2: Neighbourhoods assigned to each area";
run;

/* Frequency tables of the new grouped variables */
proc freq data=airbnb.nairobi_clean order=freq;
    tables property_group area room_group host_is_superhost / nocum;
    title "Step 2b (i) 2: Categorical variables after collapsing";
run;

/* Average log price in each new group */
proc means data=airbnb.nairobi_clean n mean maxdec=3;
    class property_group;
    var log_price;
    title "Step 2b (i) 2: Mean log(price) by property group";
run;

proc means data=airbnb.nairobi_clean n mean maxdec=3;
    class area;
    var log_price;
    title "Step 2b (i) 2: Mean log(price) by area";
run;

proc means data=airbnb.nairobi_clean n mean maxdec=3;
    class room_group;
    var log_price;
    title "Step 2b (i) 2: Mean log(price) by room group";
run;
title;

/* Number of levels and number of small levels (under 20 listings) for each categorical variable */
proc sql;
    title "Step 2b (i) 2: Number of levels in each categorical variable";
    select 'property_type' as Variable length=25,
           count(*) as Levels, sum(n < 20) as Levels_under_20, sum(n = 1) as Levels_with_1
    from (select property_type, count(*) as n from airbnb.nairobi_clean group by property_type)
    union all
    select 'neighbourhood_cleansed', count(*), sum(n < 20), sum(n = 1)
    from (select neighbourhood_cleansed, count(*) as n from airbnb.nairobi_clean group by neighbourhood_cleansed)
    union all
    select 'room_type', count(*), sum(n < 20), sum(n = 1)
    from (select room_type, count(*) as n from airbnb.nairobi_clean group by room_type)
    union all
    select 'host_is_superhost', count(*), sum(n < 20), sum(n = 1)
    from (select host_is_superhost, count(*) as n from airbnb.nairobi_clean group by host_is_superhost);
quit;

/* Save the property_type frequency table and print only the 15 most common types */
ods exclude all;
proc freq data=airbnb.nairobi_clean order=freq;
    tables property_type / nocum;
    ods output OneWayFreqs = work.pt_freq;
run;
ods exclude none;

proc print data=work.pt_freq(obs=15) noobs label;
    var property_type frequency percent;
    title "Step 2b (i) 2: 15 most common property types (of 71)";
run;
title;

proc print data=work.pt_freq(obs=15) noobs label;
    var property_type frequency percent;
    title "Step 2b (i) 2: 15 most common property types (of 69)";
run;
title;



/*****************************************************
 Step 2b (i) 3: Missing values in numeric predictors
*****************************************************/

/* Part A: Restore original values in the clean data (undo the earlier fill-in) */
options dkricond=nowarn;

proc sort data=airbnb.nairobi;
    by id;
run;

proc sort data=airbnb.nairobi_clean;
    by id;
run;

data airbnb.nairobi_clean;
    merge airbnb.nairobi_clean(in=inclean
              drop=bedrooms beds minimum_nights maximum_nights reviews_per_month rating_group)
          airbnb.nairobi(keep=id bedrooms beds minimum_nights maximum_nights reviews_per_month);
    by id;
    if inclean;
    /* Recreate bathrooms and shared_bath from bathrooms_text, as in Step 2b (i) 1 */
    if index(lowcase(bathrooms_text), 'half-bath') > 0 then bathrooms = 0.5;
    else bathrooms = input(scan(bathrooms_text, 1, ' '), ?? best12.);
    if missing(bathrooms_text) then shared_bath = .;
    else shared_bath = (index(lowcase(bathrooms_text), 'shared') > 0);
run;

options dkricond=error;

/* Part B: Missing values step - results saved to a new data set, airbnb.nairobi_final */

/* Numeric predictors kept after the multicollinearity check */
%let numvars_reduced = accommodates bedrooms beds bathrooms latitude longitude
                       minimum_nights maximum_nights availability_30 availability_365
                       number_of_reviews number_of_reviews_ltm number_of_reviews_l30d
                       review_scores_rating reviews_per_month;

/* Count missing values in each numeric predictor (before) */
proc means data=airbnb.nairobi_clean n nmiss maxdec=0;
    var &numvars_reduced;
    title "Step 2b (i) 3: Missing values in numeric predictors (before)";
run;

/* Check whether missing review scores are the listings with no reviews */
proc sql;
    title "Step 2b (i) 3: Missing review scores compared with number of reviews";
    select sum(missing(review_scores_rating))                            as rating_missing,
           sum(number_of_reviews = 0)                                    as zero_reviews,
           sum(missing(review_scores_rating) and number_of_reviews = 0) as missing_and_zero,
           sum(missing(reviews_per_month) and number_of_reviews = 0)    as rpm_missing_and_zero
    from airbnb.nairobi_clean;
quit;

/* Set reviews_per_month to 0, group review_scores_rating, fill shared_bath - save as nairobi_final */
data airbnb.nairobi_final;
    set airbnb.nairobi_clean;
    length rating_group $14;
    /* Listings with no reviews have 0 reviews per month */
    if number_of_reviews = 0 then reviews_per_month = 0;
    /* Review rating grouped, with listings that have no reviews as their own group */
    if missing(review_scores_rating) then rating_group = 'No reviews';
    else if review_scores_rating < 4.5  then rating_group = 'Below 4.5';
    else if review_scores_rating < 4.8  then rating_group = '4.5 to 4.79';
    else if review_scores_rating < 4.95 then rating_group = '4.8 to 4.94';
    else rating_group = '4.95 to 5.0';
    /* Listings with no bathroom information are set to private bathroom (most common) */
    if missing(shared_bath) then shared_bath = 0;
    label rating_group = "Review rating (grouped)"
          bathrooms    = "Number of bathrooms"
          shared_bath  = "Shared bathroom (1 = yes)";
run;

/* Fill the few missing values in bedrooms, beds, bathrooms and nights with the median */
proc stdize data=airbnb.nairobi_final out=airbnb.nairobi_final
            reponly method=median;
    var bedrooms beds bathrooms minimum_nights maximum_nights;
run;

/* Confirm there are no missing values left in the numeric predictors used in the models (after) */
proc means data=airbnb.nairobi_final n nmiss median maxdec=2;
    var accommodates bedrooms beds bathrooms latitude longitude
        minimum_nights maximum_nights availability_30 availability_365
        number_of_reviews number_of_reviews_ltm number_of_reviews_l30d
        reviews_per_month shared_bath;
    title "Step 2b (i) 3: Missing values in numeric predictors (after)";
run;

/* Number of listings and mean log price in each review rating group */
proc means data=airbnb.nairobi_final n mean maxdec=3;
    class rating_group;
    var log_price;
    title "Step 2b (i) 3: Listings and mean log(price) by review rating group";
run;
title;

 




/*****************************************************
 Step 2b (i) 4: Feature engineering and standardizing
*****************************************************/

/* Plot accommodates against log price */
proc sgplot data=airbnb.nairobi_final;
    scatter x=accommodates y=log_price / transparency=0.9 markerattrs=(symbol=circlefilled size=5);
    pbspline x=accommodates y=log_price / nomarkers lineattrs=(color=red thickness=2);
    yaxis label="Natural log of price";
    title "log(price) vs accommodates";
run;

/* Plot bedrooms against log price */
proc sgplot data=airbnb.nairobi_final;
    scatter x=bedrooms y=log_price / transparency=0.9 markerattrs=(symbol=circlefilled size=5);
    pbspline x=bedrooms y=log_price / nomarkers lineattrs=(color=red thickness=2);
    yaxis label="Natural log of price";
    title "log(price) vs bedrooms";
run;

/* Plot latitude against log price */
proc sgplot data=airbnb.nairobi_final;
    scatter x=latitude y=log_price / transparency=0.9 markerattrs=(symbol=circlefilled size=5);
    pbspline x=latitude y=log_price / nomarkers lineattrs=(color=red thickness=2);
    yaxis label="Natural log of price";
    title "log(price) vs latitude";
run;

/* Plot longitude against log price */
proc sgplot data=airbnb.nairobi_final;
    scatter x=longitude y=log_price / transparency=0.9 markerattrs=(symbol=circlefilled size=5);
    pbspline x=longitude y=log_price / nomarkers lineattrs=(color=red thickness=2);
    yaxis label="Natural log of price";
    title "log(price) vs longitude";
run;

/* Plot availability_30 against log price */
proc sgplot data=airbnb.nairobi_final;
    scatter x=availability_30 y=log_price / transparency=0.9 markerattrs=(symbol=circlefilled size=5);
    pbspline x=availability_30 y=log_price / nomarkers lineattrs=(color=red thickness=2);
    yaxis label="Natural log of price";
    title "log(price) vs availability_30";
run;

/* Create log(x + 1) versions of bedrooms, beds and bathrooms */
data work.fe;
    set airbnb.nairobi_final;
    log_bedrooms  = log(bedrooms + 1);
    log_beds      = log(beds + 1);
    log_bathrooms = log(bathrooms + 1);
    label log_bedrooms  = "Log of (bedrooms + 1)"
          log_beds      = "Log of (beds + 1)"
          log_bathrooms = "Log of (bathrooms + 1)";
run;

/* Skewness of bedrooms, beds and bathrooms before and after the log transformation */
proc means data=work.fe n mean skewness maxdec=3;
    var bedrooms log_bedrooms beds log_beds bathrooms log_bathrooms;
    title "Skewness before and after log(x + 1)";
run;

/* Plot log of bedrooms against log price */
proc sgplot data=work.fe;
    scatter x=log_bedrooms y=log_price / transparency=0.9 markerattrs=(symbol=circlefilled size=5);
    pbspline x=log_bedrooms y=log_price / nomarkers lineattrs=(color=red thickness=2);
    yaxis label="Natural log of price";
    title "log(price) vs log(bedrooms + 1)";
run;

/* Numeric predictors to standardize */
%let stdvars = accommodates log_bedrooms log_beds log_bathrooms latitude longitude
               minimum_nights maximum_nights availability_30 availability_365
               number_of_reviews number_of_reviews_ltm number_of_reviews_l30d
               reviews_per_month;

/* Standardize numeric predictors (z-scores); keep originals and add z_ versions */
proc stdize data=work.fe out=work.fe_std method=std sprefix=z_ oprefix;
    var &stdvars;
run;

/* Add squared terms made from the standardized variables - save as nairobi_model */
data airbnb.nairobi_model;
    set work.fe_std;
    z_accommodates_sq = z_accommodates**2;
    z_latitude_sq     = z_latitude**2;
    z_longitude_sq    = z_longitude**2;
    label z_accommodates_sq = "Squared standardized accommodates"
          z_latitude_sq     = "Squared standardized latitude"
          z_longitude_sq    = "Squared standardized longitude";
run;

/* Check that standardized variables have mean 0 and standard deviation 1 */
proc means data=airbnb.nairobi_model n mean std min max maxdec=3;
    var z_: ;
    title "Standardized and squared variables";
run;

/* Model fit with the original numeric predictors */
proc reg data=airbnb.nairobi_final plots=none;
    model log_price = accommodates bedrooms beds bathrooms latitude longitude
                      minimum_nights maximum_nights availability_30 availability_365
                      number_of_reviews number_of_reviews_ltm number_of_reviews_l30d
                      reviews_per_month;
    ods select FitStatistics;
    title "Model fit - original numeric predictors";
run;
quit;

/* Model fit with the engineered and standardized predictors */
proc reg data=airbnb.nairobi_model plots=none;
    model log_price = z_accommodates z_log_bedrooms z_log_beds z_log_bathrooms
                      z_latitude z_longitude z_minimum_nights z_maximum_nights
                      z_availability_30 z_availability_365 z_number_of_reviews
                      z_number_of_reviews_ltm z_number_of_reviews_l30d z_reviews_per_month
                      z_accommodates_sq z_latitude_sq z_longitude_sq;
    ods select FitStatistics;
    title "Model fit - engineered and standardized predictors";
run;
quit;
title;





/*****************************************************
 Step 2b (ii): Character (categorical) variables
*****************************************************/

/* Final frequency tables of the categorical variables used in the models */
proc freq data=airbnb.nairobi_model order=freq;
    tables property_group area room_group rating_group host_is_superhost shared_bath / nocum;
    title "Categorical variables used in the models";
run;

/* Mean log price by superhost status */
proc means data=airbnb.nairobi_model n mean maxdec=3;
    class host_is_superhost;
    var log_price;
    title "Mean log(price) by superhost status";
run;

/* Mean log price by shared bathroom */
proc means data=airbnb.nairobi_model n mean maxdec=3;
    class shared_bath;
    var log_price;
    title "Mean log(price) by shared bathroom (1 = yes)";
run;

/* Number of non-missing values and levels in categorical variables from the data dictionary */
proc sql;
    title "Categorical variables that cannot be used (empty or one value)";
    select 'host_response_time' as Variable length=25,
           count(host_response_time) as Non_missing, count(distinct host_response_time) as Levels
    from airbnb.nairobi_model
    union all
    select 'host_response_rate', count(host_response_rate), count(distinct host_response_rate)
    from airbnb.nairobi_model
    union all
    select 'host_acceptance_rate', count(host_acceptance_rate), count(distinct host_acceptance_rate)
    from airbnb.nairobi_model
    union all
    select 'instant_bookable', count(instant_bookable), count(distinct instant_bookable)
    from airbnb.nairobi_model
    union all
    select 'neighborhood_overview', count(neighborhood_overview), count(distinct neighborhood_overview)
    from airbnb.nairobi_model
    union all
    select 'has_availability', count(has_availability), count(distinct has_availability)
    from airbnb.nairobi_model;
quit;
title;

/* Frequency tables of the categorical variables not shown in Step 2b (i) 2 */
proc freq data=airbnb.nairobi_model order=freq;
    tables rating_group host_is_superhost shared_bath / nocum;
    title "Other categorical variables used in the models";
run;
title;







/*****************************************************
 Step 2c: Split data into train (80%) and test (20%)
*****************************************************/

/* Randomly select 80% of listings for training; keep all listings with a Selected flag */
proc surveyselect data=airbnb.nairobi_model out=work.split
                  method=srs samprate=0.80 seed=12345 outall;
run;

/* Create the training and testing data sets */
data airbnb.train airbnb.test;
    set work.split;
    if selected = 1 then output airbnb.train;
    else output airbnb.test;
run;

/* Add a sample label for comparing the two samples */
data work.split_check;
    set work.split;
    length sample $8;
    if selected = 1 then sample = 'Train';
    else sample = 'Test';
run;

/* Number and percent of listings in each sample */
proc freq data=work.split_check;
    tables sample / nocum;
    title "Number of listings in the training and testing samples";
run;

/* Compare log price in the training and testing samples */
proc means data=work.split_check n mean std min max maxdec=3;
    class sample;
    var log_price;
    title "log(price) in the training and testing samples";
run;

/* Compare room type and area in the training and testing samples */
proc freq data=work.split_check;
    tables (room_group area) * sample / nofreq norow nopercent;
    title "Room type and area in the training and testing samples (column %)";
run;
title;



/*****************************************************
 Step 2d: LASSO regression with PROC GLMSELECT
*****************************************************/

/* Fit LASSO on the training data; choose the model by 10-fold cross-validation; report test error */
ods graphics on;
proc glmselect data=airbnb.train testdata=airbnb.test seed=12345
               plots=(coefficients criteria ase);
    class property_group area room_group rating_group host_is_superhost;
    model log_price = z_accommodates z_log_bedrooms z_log_beds z_log_bathrooms
                      z_latitude z_longitude z_minimum_nights z_maximum_nights
                      z_availability_30 z_availability_365 z_number_of_reviews
                      z_number_of_reviews_ltm z_number_of_reviews_l30d z_reviews_per_month
                      z_accommodates_sq z_latitude_sq z_longitude_sq shared_bath
                      property_group area room_group rating_group host_is_superhost
                      / selection=lasso(choose=cv stop=none) cvmethod=random(10);
    /* Predicted log price for the training and testing listings */
    score data=airbnb.train out=work.lasso_train predicted=p_lasso residual=r_lasso;
    score data=airbnb.test  out=work.lasso_test  predicted=p_lasso residual=r_lasso;
    title "LASSO regression - log(price)";
run;

/* Combine predictions and calculate squared errors on the log scale and in KES */
data work.lasso_scored;
    set work.lasso_train(in=intrain) work.lasso_test;
    length sample $5;
    if intrain then sample = 'Train';
    else sample = 'Test';
    sq_err_log  = (log_price - p_lasso)**2;
    pred_kes    = exp(p_lasso);
    sq_err_kes  = (price - pred_kes)**2;
run;

/* RMSE for the training and testing samples */
proc sql;
    title "LASSO regression - RMSE for training and testing samples";
    select sample,
           count(*)               as N,
           sqrt(mean(sq_err_log)) as RMSE_log   format=8.4 label="RMSE (log price)",
           sqrt(mean(sq_err_kes)) as RMSE_KES   format=comma10.0 label="RMSE (KES)"
    from work.lasso_scored
    group by sample
    order by sample desc;
quit;

/* Assumption check: residuals vs predicted values (linearity and constant variance) */
proc sgplot data=work.lasso_train;
    scatter x=p_lasso y=r_lasso / transparency=0.9 markerattrs=(symbol=circlefilled size=5);
    loess x=p_lasso y=r_lasso / nomarkers lineattrs=(color=red thickness=2);
    refline 0 / axis=y lineattrs=(color=black);
    xaxis label="Predicted log(price)";
    yaxis label="Residual";
    title "LASSO regression - residuals vs predicted values (training data)";
run;

/* Assumption check: distribution of residuals (normality) */
proc univariate data=work.lasso_train;
    var r_lasso;
    histogram r_lasso / normal;
    qqplot r_lasso / normal(mu=est sigma=est);
    inset n mean std skewness kurtosis / position=ne;
    ods select Moments Histogram QQPlot;
    title "LASSO regression - distribution of residuals (training data)";
run;
title;





/*****************************************************
 Step 2e: Decision tree with PROC HPSPLIT
*****************************************************/

/* Location of the scoring code file (same folder as the airbnb library) */
%let scorefile = %sysfunc(pathname(airbnb))/hpsplit_score.sas;

/* Grow a regression tree on the training data and prune it with 10-fold cross-validation */
ods graphics on;
proc hpsplit data=airbnb.train seed=12345 cvmethod=random(10) maxdepth=10;
    class property_group area room_group rating_group host_is_superhost;
    model log_price = accommodates bedrooms beds bathrooms latitude longitude
                      minimum_nights maximum_nights availability_30 availability_365
                      number_of_reviews number_of_reviews_ltm number_of_reviews_l30d
                      reviews_per_month shared_bath
                      property_group area room_group rating_group host_is_superhost;
    grow variance;
    prune costcomplexity;
    /* Save the scoring code to a file */
    code file="&scorefile";
    title "Decision tree - log(price)";
run;

/* Score the training data with the tree's scoring code */
data work.tree_train;
    set airbnb.train;
    %include "&scorefile";
run;

/* Score the hold-out test data with the tree's scoring code */
data work.tree_test;
    set airbnb.test;
    %include "&scorefile";
run;

/* Combine predictions and calculate squared errors on the log scale and in KES */
data work.tree_scored;
    set work.tree_train(in=intrain) work.tree_test;
    length sample $5;
    if intrain then sample = 'Train';
    else sample = 'Test';
    sq_err_log = (log_price - P_log_price)**2;
    pred_kes   = exp(P_log_price);
    sq_err_kes = (price - pred_kes)**2;
run;

/* RMSE for the training and testing samples */
proc sql;
    title "Decision tree - RMSE for training and testing samples";
    select sample,
           count(*)               as N,
           sqrt(mean(sq_err_log)) as RMSE_log format=8.4 label="RMSE (log price)",
           sqrt(mean(sq_err_kes)) as RMSE_KES format=comma10.0 label="RMSE (KES)"
    from work.tree_scored
    group by sample
    order by sample desc;
quit;

/* Compare RMSE of the decision tree with the LASSO regression */
data work.compare_rmse;
    length model $16;
    set work.lasso_scored(in=inlasso keep=sample sq_err_log sq_err_kes)
        work.tree_scored(keep=sample sq_err_log sq_err_kes);
    if inlasso then model = 'LASSO regression';
    else model = 'Decision tree';
run;

proc sql;
    title "RMSE comparison - LASSO regression vs decision tree";
    select model,
           sample,
           sqrt(mean(sq_err_log)) as RMSE_log format=8.4 label="RMSE (log price)",
           sqrt(mean(sq_err_kes)) as RMSE_KES format=comma10.0 label="RMSE (KES)"
    from work.compare_rmse
    group by model, sample
    order by model desc, sample desc;
quit;
title;




/*****************************************************
 Step 2f: Random forest with PROC HPFOREST
*****************************************************/

/* Location of the saved random forest model file */
%let rffile = %sysfunc(pathname(airbnb))/rf_model.bin;

/* Grow a random forest of 200 trees on the training data */
proc hpforest data=airbnb.train seed=12345 maxtrees=200 vars_to_try=7
              trainfraction=0.6 leafsize=5 maxdepth=20;
    target log_price / level=interval;
    input accommodates bedrooms beds bathrooms latitude longitude
          minimum_nights maximum_nights availability_30 availability_365
          number_of_reviews number_of_reviews_ltm number_of_reviews_l30d
          reviews_per_month shared_bath / level=interval;
    input property_group area room_group rating_group host_is_superhost / level=nominal;
    /* Save the forest so it can score the test data */
    save file="&rffile";
    title "Random forest - log(price)";
run;

/* Score the training data with the saved forest */
proc hp4score data=airbnb.train;
    id id log_price price;
    score file="&rffile" out=work.rf_train;
run;

/* Score the hold-out test data with the saved forest */
proc hp4score data=airbnb.test;
    id id log_price price;
    score file="&rffile" out=work.rf_test;
run;

/* Combine predictions and calculate squared errors on the log scale and in KES */
data work.rf_scored;
    set work.rf_train(in=intrain) work.rf_test;
    length sample $5;
    if intrain then sample = 'Train';
    else sample = 'Test';
    sq_err_log = (log_price - P_log_price)**2;
    pred_kes   = exp(P_log_price);
    sq_err_kes = (price - pred_kes)**2;
run;

/* RMSE for the training and testing samples */
proc sql;
    title "Random forest - RMSE for training and testing samples";
    select sample,
           count(*)               as N,
           sqrt(mean(sq_err_log)) as RMSE_log format=8.4 label="RMSE (log price)",
           sqrt(mean(sq_err_kes)) as RMSE_KES format=comma10.0 label="RMSE (KES)"
    from work.rf_scored
    group by sample
    order by sample desc;
quit;

/* Compare RMSE of all three models */
data work.compare_all;
    length model $16;
    set work.lasso_scored(in=inlasso keep=sample sq_err_log sq_err_kes)
        work.tree_scored(in=intree keep=sample sq_err_log sq_err_kes)
        work.rf_scored(keep=sample sq_err_log sq_err_kes);
    if inlasso then model = 'LASSO regression';
    else if intree then model = 'Decision tree';
    else model = 'Random forest';
run;

proc sql;
    title "RMSE comparison - LASSO regression, decision tree and random forest";
    select model,
           sample,
           sqrt(mean(sq_err_log)) as RMSE_log format=8.4 label="RMSE (log price)",
           sqrt(mean(sq_err_kes)) as RMSE_KES format=comma10.0 label="RMSE (KES)"
    from work.compare_all
    group by model, sample
    order by model, sample desc;
quit;
title;

