##########################################################
# Create edx set, validation set (final hold-out test set)
##########################################################

# Note: this process could take a couple of minutes

if(!require(tidyverse)) install.packages("tidyverse", repos = "http://cran.us.r-project.org")
if(!require(caret)) install.packages("caret", repos = "http://cran.us.r-project.org")
if(!require(data.table)) install.packages("data.table", repos = "http://cran.us.r-project.org")
if(!require(lubridate)) install.packages("lubridate", repos = "http://cran.us.r-project.org")

library(tidyverse)
library(caret)
library(data.table)
library(lubridate)

# MovieLens 10M dataset:
# https://grouplens.org/datasets/movielens/10m/
# http://files.grouplens.org/datasets/movielens/ml-10m.zip

dl <- tempfile()
download.file("http://files.grouplens.org/datasets/movielens/ml-10m.zip", dl)

ratings <- fread(text = gsub("::", "\t", readLines(unzip(dl, "ml-10M100K/ratings.dat"))),
                 col.names = c("userId", "movieId", "rating", "timestamp"))

movies <- str_split_fixed(readLines(unzip(dl, "ml-10M100K/movies.dat")), "\\::", 3)
colnames(movies) <- c("movieId", "title", "genres")

# if using R 3.6 or earlier:
#movies <- as.data.frame(movies) %>% mutate(movieId = as.numeric(levels(movieId))[movieId],
#                                           title = as.character(title),
#                                           genres = as.character(genres))
# if using R 4.0 or later:
movies <- as.data.frame(movies) %>% mutate(movieId = as.numeric(movieId),
                                           title = as.character(title),
                                           genres = as.character(genres))


movielens <- left_join(ratings, movies, by = "movieId")

# Validation set will be 10% of MovieLens data
set.seed(1, sample.kind="Rounding") # if using R 3.5 or earlier, use `set.seed(1)`
test_index <- createDataPartition(y = movielens$rating, times = 1, p = 0.1, list = FALSE)
edx <- movielens[-test_index,]
temp <- movielens[test_index,]

# Make sure userId and movieId in validation set are also in edx set
validation <- temp %>% 
  semi_join(edx, by = "movieId") %>%
  semi_join(edx, by = "userId")

# Add rows removed from validation set back into edx set
removed <- anti_join(temp, validation)
edx <- rbind(edx, removed)

rm(dl, ratings, movies, test_index, temp, movielens, removed)

##########################################################

# Data wrangling

##########################################################

head(edx)

#convert timestamp into date

edx <- edx %>% mutate(year_rated = year(as_datetime(timestamp)))

#extract release date from title column and calculate age of movie
#when rating is performed to explore age effect on rating

edx <- edx %>% mutate(title = str_replace(title,"^(.+)\\s\\((\\d{4})\\)$","\\1__\\2" )) %>% 
  separate(title,c("title","year_released"),"__")

edx <- edx %>%
  mutate(age_when_rated = as.numeric(year_rated) - as.numeric(year_released))

edx <- edx %>%
  filter(year_released < 2018 & year_released > 1900) %>%
  filter(age_when_rated > 0)

head(edx)

#perform same data wrangling on validation dataset

validation <- validation %>% 
  mutate(year_rated = year(as_datetime(timestamp)))

validation <- validation %>% 
  mutate(title = str_replace(title,"^(.+)\\s\\((\\d{4})\\)$","\\1__\\2" )) %>% 
  separate(title,c("title","year_released"),"__") 

validation <- validation %>%
  mutate(age_when_rated = as.numeric(year_rated) - as.numeric(year_released))

validation <- validation %>%
  filter(year_released < 2018 & year_released > 1900) %>%
  filter(age_when_rated > 0)

##########################################################

# Data visualization and exploration

##########################################################

#learn more about the dataset through summary and visualization

head(edx)

edx %>%
  summarize(n_users = n_distinct(userId),
            n_movies = n_distinct(movieId))

mean(edx$rating)
sd(edx$rating)

#most rated movies
edx %>%
  group_by(title) %>%
  summarise(count = n(), title = title[1]) %>%
  top_n(10, count) %>%
  arrange(desc(count))

#number of ratings per user
edx %>%
  group_by(userId) %>%
  summarise(n = n()) %>%
  ggplot(aes(n)) +
  geom_histogram(fill = "red", color = "black", bins = 10) +
  scale_x_log10()

#rating distributions
edx %>%
  group_by(rating) %>%
  ggplot(aes(rating)) +
  geom_bar(fill = "red", color = "black")

#genres distribution
edx %>%
  separate_rows(genres, sep = "\\|") %>%
  mutate(value = 1) %>%
  group_by(genres) %>%
  summarize(n = n()) %>%
  arrange(desc(n))

#age of movie vs mean rating
edx %>%
  group_by(age_when_rated) %>%
  summarise(mean_age = mean(rating)) %>%
  ggplot(aes(age_when_rated, mean_age)) +
  geom_point() +
  geom_smooth(method = "loess", formula = y ~ x) +
  geom_line(aes(,mean(edx$rating)))

##########################################################

# Analysis

##########################################################

#create training and test set using the edx set only
options(dplyr.summarise.inform = FALSE)
set.seed(20, sample.kind = "Rounding")

test_index <- createDataPartition(y = edx$rating, times = 1, p = 0.2, list = FALSE)
training_set <- edx[-test_index,]
test_set <- edx[test_index,]

test_set <- test_set %>%
  semi_join(training_set, by = "movieId") %>%
  semi_join(training_set, by = "userId")

validation <- validation %>%
  semi_join(training_set, by = "movieId") %>%
  semi_join(training_set, by = "userId")

#define RMSE as our evaluation benchmark

RMSE <- function(true_rating, predicted_rating){
  sqrt(mean((true_rating - predicted_rating)^2))
}

#1.mean model, naive approach to use mean to estimate rating

model_mean <- mean(training_set$rating)
model_mean

rmse_mean <- RMSE(validation$rating, model_mean)
rmse_mean

rmse_results <- tibble(method = "Mean model", RMSE = rmse_mean)
rmse_results

#2.age model, use the age of movie to estimate rating (age bias)

model_age <- training_set %>%
  group_by(age_when_rated) %>%
  summarize(b_a = mean(rating - model_mean))

predicted_age <- model_mean + validation %>%
  left_join(model_age, by='age_when_rated') %>%
  pull(b_a)

rmse_age <- RMSE(validation$rating, predicted_age)
rmse_age

rmse_results <- bind_rows(rmse_results, tibble(method = "Rating Age model",
                                                   RMSE = rmse_age))

rmse_results

#3.movie model to predict rating (movie bias)

model_movie <- training_set %>%
  group_by(movieId) %>%
  summarize(b_m = mean(rating - model_mean))

predicted_movie <- model_mean + validation %>%
  left_join(model_movie, by = 'movieId') %>%
  pull(b_m) 

rmse_movie <- RMSE(validation$rating, predicted_movie)
rmse_movie

rmse_results <- bind_rows(rmse_results, tibble(method = "MovieID model",
                                               RMSE = rmse_movie))

#4.user model to predict rating (user bias)

model_user <- training_set %>%
  group_by(userId) %>%
  summarize(b_u = mean(rating - model_mean))

predicted_user <- model_mean + validation %>%
  left_join(model_user, by = 'userId') %>%
  pull(b_u)

rmse_user <- RMSE(validation$rating, predicted_user)
rmse_user

rmse_results <- bind_rows(rmse_results, tibble(method = "UserID model",
                                               RMSE = rmse_user))

#5.genre model to predict rating (genre bias)

model_genre <- training_set %>%
  group_by(genres) %>%
  summarize(b_g = mean(rating - model_mean))

predicted_genre <- model_mean + validation %>%
  left_join(model_genre, by = 'genres') %>%
  pull(b_g)

rmse_genre <- RMSE(validation$rating, predicted_genre)
rmse_genre

rmse_results <- bind_rows(rmse_results, tibble(method = "Genre model",
                                               RMSE = rmse_genre))

#6.release date model to predict rating (release date bias)

model_release <- training_set %>%
  group_by(year_released) %>%
  summarize(b_r = mean(rating - model_mean))

predicted_release <- model_mean + validation %>%
  left_join(model_release, by = 'year_released') %>%
  pull(b_r)

rmse_release <- RMSE(validation$rating, predicted_release)
rmse_release

rmse_results <- bind_rows(rmse_results, tibble(method = "Release date model",
                                               RMSE = rmse_release))

#7.combined bias model: movieId + userId

user_effect <- training_set %>%
  left_join(model_movie, by='movieId') %>%
  group_by(userId) %>%
  summarize(b_u = mean(rating - model_mean - b_m))

predicted_m_u <- validation %>%
  left_join(model_movie, by = 'movieId') %>%
  left_join(user_effect, by = 'userId') %>%
  mutate(pred = model_mean + b_m + b_u)

rmse_m_u <- RMSE(validation$rating, predicted_m_u$pred)
rmse_m_u


rmse_results <- bind_rows(rmse_results, tibble(method = "MovieID + UserID model",
                                               RMSE = rmse_m_u))

#8.combined bias model: age of rating + release date

release_effect <- training_set %>%
  left_join(model_age, by='age_when_rated') %>%
  group_by(year_released) %>%
  summarize(b_r = mean(rating - model_mean - b_a))

predicted_a_r <- validation %>%
  left_join(model_age, by = 'age_when_rated') %>%
  left_join(release_effect, by = 'year_released') %>%
  mutate(pred = model_mean + b_a + b_r)

rmse_a_r <- RMSE(validation$rating, predicted_a_r$pred)
rmse_a_r

rmse_results <- bind_rows(rmse_results, tibble(method = "Rating Age + Release date model",
                                               RMSE = rmse_a_r))

options(pillar.sigfig = 7)
rmse_results %>%
  arrange(desc(RMSE))

#9. Regularized approach using movieId + userId

lambdas <- seq(0, 10, 0.25)
rmses <- sapply(lambdas, function(l){
  
  mean <- mean(training_set$rating)
  
  b_m <- training_set %>%
    group_by(movieId) %>%
    summarize(b_m = sum(rating - mean)/(n()+l))
  
  b_u <- training_set %>%
    left_join(b_m, by='movieId') %>%
    group_by(userId) %>%
    summarize(b_u = sum(rating - mean - b_m)/(n()+l))
  
  rpred_m_u <- validation %>%
    left_join(b_m, by='movieId') %>%
    left_join(b_u, by='userId') %>%
    mutate(pred = mean + b_m + b_u) %>%
    .$pred
  
  return(RMSE(validation$rating, rpred_m_u))
})

qplot(lambdas, rmses)

rmse_rm_u <- min(rmses)
rmse_rm_u

rmse_results <- bind_rows(rmse_results, tibble(method = "Regularized Movie + User Effect Model",
                                               RMSE = rmse_rm_u))

rmse_results

rmse_results %>%
  arrange(desc(RMSE))

#10

lambdas <- seq(0, 10, 0.25)
rmses <- sapply(lambdas, function(l){
  
  mean <- mean(training_set$rating)
  
  b_m <- training_set %>%
    group_by(movieId) %>%
    summarize(b_m = sum(rating - mean)/(n()+l))
  
  b_u <- training_set %>%
    left_join(b_m, by='movieId') %>%
    group_by(userId) %>%
    summarize(b_u = sum(rating - mean - b_m)/(n()+l))
  
  b_a <- training_set %>%
    left_join(b_m, by='movieId') %>%
    left_join(b_u, by='userId') %>%
    group_by(age_when_rated) %>%
    summarize(b_a = sum(rating - mean - b_m - b_u)/(n()+l))
  
  b_r <- training_set %>%
    left_join(b_m, by='movieId') %>%
    left_join(b_u, by='userId') %>%
    left_join(b_a, by='age_when_rated') %>%
    group_by(year_released) %>%
    summarize(b_r = sum(rating - mean - b_m - b_u - b_a)/(n()+l))
  
  b_g <- training_set %>%
    left_join(b_m, by='movieId') %>%
    left_join(b_u, by='userId') %>%
    left_join(b_a, by='age_when_rated') %>%
    left_join(b_r, by='year_released') %>%
    group_by(genres) %>%
    summarize(b_g = sum(rating - mean - b_m - b_u - b_a - b_r)/(n()+l))
  
  rpred_m_u <- validation %>%
    left_join(b_m, by='movieId') %>%
    left_join(b_u, by='userId') %>%
    left_join(b_a, by='age_when_rated') %>%
    left_join(b_r, by='year_released') %>%
    left_join(b_g, by='genres') %>%
    mutate(pred = mean + b_m + b_u + b_a + b_r + b_g) %>%
    .$pred
  
  return(RMSE(validation$rating, rpred_m_u))
})

qplot(lambdas, rmses)

rmse_rcombined <- min(rmses)
rmse_rcombined

rmse_results <- bind_rows(rmse_results, tibble(method = "Regularized combined bias Model",
                                               RMSE = rmse_rcombined))

rmse_results

rmse_results %>%
  arrange(desc(RMSE))


