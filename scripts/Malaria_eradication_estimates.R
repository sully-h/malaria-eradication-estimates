# Step 0. Import libraries and set defaults

library(tidyverse)
library(ggplot2)
library(anytime)
library(readxl)
library(countrycode)

# Step 1. Import data ------------------------------------------------------------

### Most recent estimates of malaria burden by country (WHO):
burden <- data.frame(read_xlsx("source-data/WMR2021_Annex5F.xlsx", skip = 3))
colnames(burden) <- c('location', 'year', 'pop', 
                      'cases_bot', 'cases', 'cases_top',
                      'deaths_bot', 'deaths', 'deaths_top')

# Fix location (data in panel format means location names are implied downward from their first mention but not explicitly listed)
current_location <- NA
for(i in 1:nrow(burden)){if(is.na(burden$location[i])){burden$location[i] <- current_location} else {current_location <- burden$location[i]}}

# Clean location names (removing footnotes):
burden$location <- gsub("[^[:alnum:][:space:]]", "", burden$location)
burden$location <- gsub('[[:digit:]]+', '', burden$location)

# Get iso3c
burden$iso3c <- countrycode(burden$location, 'country.name', 'iso3c')

# Keep only country-level observations
burden <- burden[!is.na(burden$iso3c), ]

# Estimates of work days lost to malaria
days_lost_per_case <- 3 # This is from researchers at LSHT: 

#####
# 
# "...The number of work days lost per case are going to depend on: 1) How quickly/if treatment is received; 2) Age of person with malaria; 3) Whether it remains uncomplicated or progresses to severe; 4) various other factors, which will vary between individuals and between countries and contexts.
# 
# But, we could assume that:
#   
#  - 1 person per case loses productive time (either the adult with malaria, or one adult caring for one child with malaria – obviously, there is variation in this)
#  - 3 days (range: 1 to 7) lost per episode (taking into account a weighted average of uncomplicated and severe cases, and cases resulting in death; this is shorter than standard assumptions of duration of illness, but I think it’s reasonably and conservative to assume people return to work before they/their child are fully recovered)
# ...
# In addition, it may be worth having a look at some of the macroeconomic literature about the wider negative impacts of the presence of malaria on the economy. A human capital approach would also potentially account for the cumulative effects of loss of schooling and cognitive function on future productivity – but all of that is obviously even harder to quantify."
#####

# Converting to numeric:
for(i in c("cases_bot", "cases_top", "deaths_bot", "deaths_top")){
  burden[, i] <- as.numeric(burden[, i])
}

# Multiplying work days lost in:
burden$work_days_lost_bot <- burden$cases_bot*days_lost_per_case 
burden$work_days_lost <- burden$cases*days_lost_per_case 
burden$work_days_lost_top <- burden$cases_top*days_lost_per_case 

# Check that total matches WHO totals
round(sum(burden$cases[burden$year == 2020], na.rm =T)/1000000, 0) == 241
round(sum(burden$deaths[burden$year == 2020], na.rm =T)/1000, 0)   == 627

### Populations by country (historical and projected - UN):
estimates <- read_xlsx("source-data/WPP2019_POP_F01_1_TOTAL_POPULATION_BOTH_SEXES.xlsx", 
                       sheet = 1, skip = 16)
projections <- read_xlsx("source-data/WPP2019_POP_F01_1_TOTAL_POPULATION_BOTH_SEXES.xlsx", 
                         sheet = 2, skip = 16) # We use the "medium variant" of population projections

# Convert from wide to long
estimates <- estimates %>%  pivot_longer(
  cols = 8:ncol(estimates),
  names_to = "year",
  values_to = "population.estimated")
estimates <- estimates[!estimates$`Region, subregion, country or area *` %in% 'Less developed regions, excluding China', ] # this trips up the countrycode matching algorithm since it includes the name of the country
estimates$population.estimated <- as.numeric(estimates$population.estimated)
estimates$year <- as.numeric(estimates$year)
estimates$iso3c <- countrycode(estimates$`Region, subregion, country or area *`, "country.name", "iso3c")

projections <- projections %>%  pivot_longer(
  cols = 8:ncol(projections),
  names_to = "year",
  values_to = "population.projected")
projections <- projections[!projections$`Region, subregion, country or area *` == 'Less developed regions, excluding China', ]
projections$population.projected <- as.numeric(projections$population.projected)
projections$year <- as.numeric(projections$year)
projections$iso3c <- countrycode(projections$`Region, subregion, country or area *`, "country.name", "iso3c")

# Keep only country-level observations of population or population estimate
estimates <- estimates[!is.na(estimates$iso3c), c('iso3c', 'year', 'population.estimated')]
projections <- projections[!is.na(projections$iso3c), c('iso3c', 'year', 'population.projected')]

ggplot(estimates, aes(x=as.numeric(year), y=as.numeric(population.estimated), col=iso3c))+geom_line()+theme(legend.pos = 'none')
ggplot(projections, aes(x=as.numeric(year), y=as.numeric(population.projected), col=iso3c))+geom_line()+theme(legend.pos = 'none')

# Merge them together:
pop <- merge(estimates, projections, by = c('iso3c', 'year'), all = T)
pop$population <- pop$population.estimated # Use estimated population if available
pop$population[is.na(pop$population)] <- pop$population.projected[is.na(pop$population)] # Use projection population if not
pop <- unique(pop[!is.na(pop$year) & !is.na(pop$iso3c), c('iso3c', 'year', 'population')])
pop$population <- as.numeric(pop$population)*1000 # Source is in thousands, this converts to estimated total
pop$year <- as.numeric(pop$year)

# Check that total matches world population:
round(sum(pop$population[pop$year == 2020])/1000000, 0) == 7795

# Merge population data with malaria data
malaria <- merge(burden, pop, by = c('iso3c', 'year'), all = T)
malaria$year <- as.numeric(malaria$year)
malaria$pop <- NULL
malaria <- malaria[!is.na(malaria$year), ]
malaria$country <- countrycode(malaria$iso3c, 'iso3c', 'country.name')

# Step 2. Estimate malaria burden over the next few decades based on 2018-2020 values --------------
malaria <- malaria[malaria$year %in% 2000:2050, ] # first year of malaria burden estimates to mid-century. NB: the further from the present, the more uncertain such estimates become

# We convert the variables to numeric:
vars <- c("cases_bot", "cases", "cases_top", 
          "deaths_bot", "deaths", "deaths_top", 
          "work_days_lost", "population")
for(i in vars){malaria[, i] <- as.numeric(malaria[, i])}

# We first record the most recent values (2018-20):
for(i in unique(malaria$iso3c)){
  for(j in vars){
  malaria[malaria$iso3c == i, paste0(j, '_in_2020')] <- mean(malaria[malaria$year %in% c(2018:2020) 
                                                                & malaria$iso3c == i, j], na.rm = T)
  }
}

# Then generate the predicted value taking current population shares and adjusting for population change
malaria$population_change <- malaria$population / malaria$population_in_2020
for(i in vars){
  malaria[is.na(malaria[, i]), i] <- malaria[is.na(malaria[, i]), paste0(i, '_in_2020')]*malaria$population_change[is.na(malaria[, i])]
}

# Then remove these columns for clarity
for(i in vars){
malaria[, paste0(i, '_in_2020')] <- NULL
}
malaria$population_change <- NULL

# And make clear they are estimated in separate column
malaria$note <- NA
malaria$note[malaria$year > 2020] <- "Estimated based on 2020 values and population projections by the UN"

# Step 3. Estimate malaria burden reduced as per WHO goals (in 2021 update, but the same targets as in 2016) --------------

# One possibility:
# Source: https://reliefweb.int/report/world/who-global-technical-strategy-malaria-2016-2030-2021-update
# Note, we assume that these targets are not affected by a change in the WHOs methodology, which added about 22 000 deaths in 2020 (an upward adjustment of 3.5%).
# These targets are:
# 2025 = 75% of 2015 levels (cases (by implication work days lost), deaths)
# 2030 = 90% of 2015 levels (cases (by implication work days lost), deaths)

# Our selected scenario:
# -75% compared to 2015 levels in 2030:

# First get data by year:
# 2015
malaria_cases_2015 <- sum(malaria$cases[malaria$year == 2015], na.rm = T)
malaria_deaths_2015 <- sum(malaria$deaths[malaria$year == 2015], na.rm = T)
# 2025
malaria_cases_2025 <- sum(malaria$cases[malaria$year == 2025], na.rm = T)
malaria_deaths_2025 <- sum(malaria$deaths[malaria$year == 2025], na.rm = T)
# 2030
malaria_cases_2030 <- sum(malaria$cases[malaria$year == 2030], na.rm = T)
malaria_deaths_2030 <- sum(malaria$deaths[malaria$year == 2030], na.rm = T)

# Get multipliers
implied_decrease_cases_by_2025 <- 0.25/(malaria_cases_2025/malaria_cases_2015)
implied_decrease_deaths_by_2025 <- 0.25/(malaria_deaths_2025/malaria_deaths_2015)

# However, uncomment this line if you want to use 75% reduction by 2025 target
implied_decrease_cases_by_2025 <- implied_decrease_deaths_by_2025 <- NA

implied_decrease_cases_by_2030 <- 0.25/(malaria_cases_2030/malaria_cases_2015)
implied_decrease_deaths_by_2030 <- 0.25/(malaria_deaths_2030/malaria_deaths_2015)

# Construct multipliers (conservatively assuming linear drop):
case_decreases_by_year <- c(1, NA, NA, NA, NA, implied_decrease_cases_by_2025, NA, NA, NA, NA, implied_decrease_cases_by_2030)
case_decreases_by_year <- approx(case_decreases_by_year, n = 11)[[2]]
case_decreases_by_year <- cbind.data.frame("year" = 2020:2030, 
                                           "case_decrease" = case_decreases_by_year)
# plot(case_decreases_by_year)

death_decreases_by_year <- c(1, NA, NA, NA, NA, implied_decrease_deaths_by_2025, NA, NA, NA, NA, implied_decrease_deaths_by_2030)
death_decreases_by_year <- approx(death_decreases_by_year, n = 11)[[2]]
death_decreases_by_year <- cbind.data.frame("year" = 2020:2030, 
                                            "death_decrease" = death_decreases_by_year)
# plot(death_decreases_by_year)

# Merge these into main data (assuming no change before or after):
malaria <- merge(malaria, case_decreases_by_year, by = 'year', all = T)
malaria$case_decrease[malaria$year < 2020] <- 1
malaria$case_decrease[malaria$year > 2030] <- case_decreases_by_year$case_decrease[case_decreases_by_year$year == 2030]

malaria <- merge(malaria, death_decreases_by_year, by = 'year', all = T)
malaria$death_decrease[malaria$year < 2020] <- 1
malaria$death_decrease[malaria$year > 2030] <- death_decreases_by_year$death_decrease[death_decreases_by_year$year == 2030]

# Construct scenarios based on them:
for(i in c("cases_bot", "cases", "cases_top", "work_days_lost")){
  malaria[, paste0(i, '_if_eradication')] <- malaria[, i]*malaria$case_decrease
}

for(i in c("deaths_bot", "deaths", "deaths_top")){
  malaria[, paste0(i, '_if_eradication')] <- malaria[, i]*malaria$death_decrease
}

# Generate columns showing averted outcomes if implemented:
for(i in setdiff(vars, 'population')){
  malaria[, paste0(i, '_averted')] <- malaria[, i] - malaria[, paste0(i, '_if_eradication')]
}

# Check that the procedure worked:
round(sum(malaria$cases_if_eradication[malaria$year == 2025], na.rm = T)/1000, 0) == 
  round(sum(malaria$cases[malaria$year == 2015], na.rm = T)*0.25/1000, 0)
round(sum(malaria$cases_if_eradication[malaria$year == 2030], na.rm = T)/1000, 0) == 
  round(sum(malaria$cases[malaria$year == 2015], na.rm = T)*0.10/1000, 0)

round(sum(malaria$deaths_if_eradication[malaria$year == 2025], na.rm = T)/1000, 0) == 
  round(sum(malaria$deaths[malaria$year == 2015], na.rm = T)*0.25/1000, 0)
round(sum(malaria$deaths_if_eradication[malaria$year == 2030], na.rm = T)/1000, 0) == 
  round(sum(malaria$deaths[malaria$year == 2015], na.rm = T)*0.10/1000, 0)

# Export csv:
write_csv(malaria, 'output-data/malaria_estimates.csv')

# Step 4. Get comparables --------------

# Work hours:
# Source: https://data.oecd.org/emp/labour-force.htm#indicator-chart ; https://stats.oecd.org/Index.aspx?DataSetCode=AVE_HRS
sweden_labor_force <- 5522000
sweden_annual_hours_per_worker <- 1424
sweden_hours_worked_per_week_on_main_job <- 36
sweden_work_days_yearly <- sweden_labor_force*sweden_annual_hours_per_worker/(sweden_hours_worked_per_week_on_main_job/5)

us_labor_force <- 161204000 
us_annual_hours_per_worker <- 1767  
us_hours_worked_per_week_on_main_job <- 38.7
us_work_days_yearly <- us_labor_force*us_annual_hours_per_worker/(us_hours_worked_per_week_on_main_job/5)

uk_labor_force <- 34074000
uk_annual_hours_per_worker <- 1367
uk_hours_worked_per_week_on_main_job <- 36.3
uk_work_days_yearly <- uk_labor_force*uk_annual_hours_per_worker/(uk_hours_worked_per_week_on_main_job/5)

germany_labor_force <- 43517000
germany_annual_hours_per_worker <-  1332
germany_hours_worked_per_week_on_main_job <- 34.3
germany_work_days_yearly <- germany_labor_force*germany_annual_hours_per_worker/(germany_hours_worked_per_week_on_main_job/5)

# Work hours for Nigeria:
nigeria_labor_force <- 60463000 # https://www.statista.com/statistics/1288348/number-of-people-employed-in-nigeria/#:~:text=As%20of%202022%2C%20approximately%2060,has%20remained%20above%2050%20million.
nigeria_annual_hours_per_worker  <- 1827.24
# https://ourworldindata.org/working-hours
nigeria_hours_worked_per_week_on_main_job <- 40 
nigeria_work_days_yearly <- nigeria_labor_force*nigeria_annual_hours_per_worker/(nigeria_hours_worked_per_week_on_main_job/5)

# Deaths comparisons:
deaths_from_heart_disease <- 17600000
deaths_from_cancer <- 10000000
deaths_from_lung_cancer <- 1800000
deaths_from_breast_cancer <- 685000
  
# Source: https://www.who.int/news-room/fact-sheets/detail/cancer

comparables <- rbind.data.frame(c('sweden', 'days worked', sweden_work_days_yearly),
                                c('united states', 'days worked', us_work_days_yearly),
                                c('uk', 'days worked', uk_work_days_yearly),
                                c('germany', 'days worked', germany_work_days_yearly),
                                c('world', 'deaths from heart disease', 
                                  deaths_from_heart_disease),
                                c('world', 'deaths from cancer', deaths_from_cancer),
                                c('world', 'deaths from lung cancer', deaths_from_lung_cancer),
                                c('world', 'deaths from breast cancer', deaths_from_breast_cancer))
colnames(comparables) <- c('location', 'outcome', 'value')

write_csv(comparables, 'output-data/comparables.csv')


# Step 5. Make charts --------------

malaria$world_work_days_lost_averted <- ave(malaria$work_days_lost_averted, malaria$year, FUN= function(x) sum(x, na.rm = T))
malaria$world_deaths_averted <- ave(malaria$deaths_averted, malaria$year, FUN= function(x) sum(x, na.rm = T))

malaria$deaths_averted_cumulative <- ave(malaria$deaths_averted, malaria$iso3c, FUN = function(x) cumsum(ifelse(is.na(x), 0, x)))
malaria$work_days_lost_averted_cumulative <- ave(malaria$work_days_lost_averted, malaria$iso3c, FUN = function(x) cumsum(ifelse(is.na(x), 0, x)))


ggplot(malaria[malaria$year %in% 2020:2042, ], 
       aes(x=year, y=deaths_averted_cumulative, fill=iso3c))+
  theme_minimal()+
  geom_area()+
  geom_area(aes(y=-work_days_lost_averted_cumulative/1000))+
  geom_hline(aes(yintercept = 0))+
  coord_flip()+scale_x_reverse()+guides(fill="none")+theme(legend.title = element_blank())+
  geom_hline(aes(yintercept=deaths_from_cancer, col='Annual deaths from cancer (2020)'))+
  geom_hline(aes(yintercept=-sweden_work_days_yearly/1000, col='Annual days worked in Sweden (2020)'))+
  geom_hline(aes(yintercept=-germany_work_days_yearly/1000, col='Annual days worked in Germany (2020)'))+
  geom_hline(aes(yintercept=deaths_from_lung_cancer, col='Annual deaths from lung cancer (2020)'))+
  ylab('Cumulative impact \n(<- work days gained, 000s / lives saved ->) ')+xlab('')
ggsave('plots/cumulative_impact.png', width = 8, height = 8)


ggplot(malaria[malaria$year %in% 2020:2042, ], 
       aes(x=year, y=deaths_averted, fill=iso3c))+
  theme_minimal()+
  geom_area()+
  geom_area(aes(y=-work_days_lost_averted/1000))+
  geom_hline(aes(yintercept = 0))+
  coord_flip()+scale_x_reverse()+guides(fill="none")+theme(legend.title = element_blank())+
  geom_hline(aes(yintercept=-sweden_work_days_yearly/1000, col='Annual days worked in Sweden (2020)'))+
  geom_hline(aes(yintercept=deaths_from_breast_cancer, col='Worldwide deaths from breast cancer (2020)'))+
  ylab('Yearly impact \n(<- work days gained, 000s / lives saved ->) ')+xlab('')
ggsave('plots/impact.png', width = 8, height = 8)


ggplot(malaria, aes(x=year, y=deaths_if_eradication, fill = iso3c))+geom_area(aes(y=deaths, group=iso3c), fill = 'gray')+geom_area()+theme(legend.pos = 'none')+xlab('')+ylab('')+ggtitle('Annual deaths, if eradication targets met (color), or not')
ggsave('plots/eradication_vs_current_levels.png', width = 8, height = 8)