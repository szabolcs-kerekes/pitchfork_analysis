#### Importing libraries
library(tidyverse)
library(tidytext)
library(stringr)
library(ggplot2)
library(lubridate)
library(skimr)
library(purrr)
library(data.table)
library(logger)
library(caret)

#### Loading the data
data <- read.csv('pitchfork_final.csv', stringsAsFactors = FALSE)

str(data)

head(data)

#### Data cleaning
skim(data)


# Taking care of missing values
data %>% filter(is.na(artist) == TRUE)

data <- data %>% filter(is.na(release_year) == FALSE)

data <- data %>% mutate(review_date = ymd(review_date))
max_date <- data %>% select(review_date) %>% drop_na() %>% head(1)
max_date <- max_date$review_date
data <- data %>% replace_na(list(review_date = max_date + 1, 
                                 bnm = FALSE,
                                 author_title = 'Other',
                                 genre = 'Other',
                                 label_name = 'Other',
                                 artist_name = 'NA_'))
str(data)

data <- data %>% mutate(artist = as.factor(artist),
                genre = as.factor(genre),
                author_name = as.factor(author_name),
                author_title = as.factor(author_title),
                label_name = as.factor(label_name))

# Selecting years 2016 - 2019
data <- data %>% filter(release_year >= 2016)

# Parsing review text into simple text
unique(unlist(map(data$review_text, function(x) unique(unlist(strsplit(tolower(x), split = ""))))))

temp <- map(data$review_text, function(x){ 
  x <- str_replace_all(x, 'Best new music', '')
  x <- tolower(x)
  x <- str_replace_all(x, regex("[^a-z /n]*", perl = TRUE), '')
  return(x)
}) 

data$review_text <- unlist(temp)

#### Creating the custom stop word dictionary
names <- gsub("([a-z])([A-Z])", "\\1 \\2", unique(data$artist))
names <- str_split(names, ' ')
names <- map(names, function(x) tolower(x))
names <- map(names, function(x) str_replace_all(x, regex("[^a-z /n]*", perl = TRUE), ''))

genres <- str_split(unique(data$genre), '\\/')
genres <- map(genres, function(x) tolower(x))
genres <- map(genres, function(x) str_replace_all(x, regex("[^a-z /n]*", perl = TRUE), ''))

custom_stop_words <- bind_rows(data_frame(word = c("album", "music", "songs", "band", "song",
                                                   "sounds", "albums", "sound", "record", "records", "time",
                                                   "bands", "feels", "makes", "voice",
                                                   "feel", "track", "tracks", "hes", "shes", "dont", "doesnt", 
                                                   "im", "raps", "rappers", "aint",
                                                   "artist", "artists", "isnt", unique(unlist(names)), unlist(genres)), 
                                          lexicon = c("custom")), stop_words)


#### Sentiment analysis
sent_afinn <- get_sentiments('afinn')

afinn_scores <- map(data$review_text, function(x){
  text <- strsplit(x, ' ')
  
  text <- data_frame('word' = unlist(text))
  
  text <- text %>% 
    filter(word != '') %>%
    anti_join(stop_words) %>% 
    inner_join(sent_afinn) %>% 
    summarise(afinn_score = mean(score) / 5)
  
  return(text$afinn_score)
})

data$afinn_score <- unlist(afinn_scores)

data_train <- data %>% filter(year(review_date) < 2019)

data_test <- data %>% filter(year(review_date) == 2019)

ggplot(data = data_train, aes(x = score, y = afinn_score)) +
  geom_point() +
  facet_wrap(~release_year) + 
  geom_smooth(method = 'lm')

ggplot(data = data_train, aes(x = score, y = afinn_score)) +
  geom_point() +
  facet_wrap(~genre + release_year) + 
  geom_smooth(method = 'lm')

ggplot(data = data_train, aes(x = score)) +
  geom_bar() +
  facet_wrap(~release_year)

#### OLS modelling
nrow(data_test) - sum(data_test$author_name %in% data_train$author_name)

unique(data_test$author_name)[!(unique(data_test$author_name) %in% unique(data_train$author_name))]

unique(data_test$author_title)[!(unique(data_test$author_title) %in% unique(data_train$author_title))]

vars_lev <- c('genre', 'afinn_score', 'bnm')

lev1model <- paste0("score ~ ",paste(vars_lev,collapse = " + "))

ols_modeller <- function(x, data_train) {
  set.seed(42)
  data_train_temp <- data_train
  model_name <- as.character(x)
  model <- train(
    formula(model_name),
    data = data_train,
    method = "lm",
    trControl = train_control)
  list_res <- model
  return(list_res)
}

train_control <- trainControl(method = "cv", number = 10, verboseIter = F)

model <- ols_modeller(lev1model, data_train)

data_predicted <- data_test %>% 
  mutate(predicted_score = predict(model, newdata = data_test))

ggplot(data = data_predicted, aes(x = score, y = predicted_score)) +
  geom_point() +
  xlim(2, 10) +
  ylim(2, 10) +
  geom_smooth(method = 'lm')

#### Word frequency

summary(data$score)

q1 <- 6.8
q2 <- 7.3
q3 <- 7.7

q1_data <- data %>% filter(score < 6.8)

q2_data <- data %>% filter(score >= 6.8 & score < 7.7)

q3_data <- data %>% filter(score > 7.7)

top_worder <- function(data_input){
  
  text_list <- list()
  log_info('List created')
  
  for (i in 1:nrow(data_input)){
    data <- data_input %>% slice(i) %>% select(artist, review_text)
    #log_info('Data slices')

    text <- strsplit(data$review_text, ' ')
    #log_info('Text split done')
    text <- data_frame(word = unlist(text))
    #log_info('Added word variable')
    text <- text %>% 
      filter(word != '')
    #log_info('Filtered for empty')
    text <- text %>% 
      anti_join(custom_stop_words)
    #log_info('Anti-join done')
    total_rows <- nrow(text)
    text <- text %>% 
      group_by(word) %>% 
      count() %>% 
      summarize(count = n, total_count = total_rows) %>% 
      arrange(-count) %>%
      head(20)
    
    text_list[[i]] <- text 
  }
  
  trial <- rbindlist(text_list)
  
  all_words <- sum(trial$total_count) / length(unique(trial$total_count))
  
  top_words <- trial %>% 
    group_by(word) %>% 
    summarise(total = sum(count), all_words = all_words, share = total/all_words) %>% 
    arrange(-total) 
  
  return(top_words)
}

q1_data_f <- top_worder(q1_data) %>% mutate(segment = 'q1') %>% head(10)

q2_data_f <- top_worder(q2_data) %>% mutate(segment = 'q2') %>% head(10)

q3_data_f <- top_worder(q3_data) %>% mutate(segment = 'q3') %>% head(10)

all_qs <- rbindlist(list(q1_data_f, q2_data_f, q3_data_f))

ggplot(all_qs, aes(x = reorder(word, share), share, fill = segment)) +
  geom_col() +
  facet_wrap(~segment, ncol = 3, scales = 'free') +
  coord_flip()

genre_list <- list()
i = 1
for (g in unique(q1_data$genre)){
  data_temp <- q1_data %>% filter(genre == g)
  data_temp <- top_worder(data_temp) %>% mutate(segment = g) %>% head(10)
  genre_list[[i]] <- data_temp
  i = i + 1
}

all_genres_freq <- rbindlist(genre_list)

ggplot(all_genres_freq, aes(x = reorder(word, share), share, fill = segment)) +
  geom_col(show.legend = FALSE) +
  facet_wrap(~segment, ncol = 3, scales = 'free') +
  coord_flip()

genre_freqer <- function(data){
  genre_list <- list()
  i = 1
  for (g in unique(data$genre)){
    data_temp <- data %>% filter(genre == g)
    data_temp <- top_worder(data_temp) %>% mutate(segment = g) %>% head(10)
    genre_list[[i]] <- data_temp
    i = i + 1
  }
  
  all_genres_freq <- rbindlist(genre_list)
  
  return(all_genres_freq)
}

q3_data_genre_f <- genre_freqer(q3_data)

ggplot(q3_data_genre_f, aes(x = reorder(word, share), share, fill = segment)) +
  geom_col(show.legend = FALSE) +
  facet_wrap(~segment, ncol = 3, scales = 'free') +
  coord_flip()

ggplot(data = q3_data, aes(x = genre)) +
  geom_bar()

#### Inverse frequency

tf_idfer <- function(data_input){
  text_list <- list()
  
  for (i in 1:nrow(data_input)){
    work_data <- data_input %>% slice(i) %>% select(artist, album, review_text)
    
    artist_to_use <- paste(work_data$artist, work_data$album, sep = '_')
    #log_info('Data slices')
    
    text <- strsplit(work_data$review_text, ' ')
    #log_info('Text split done')
    text <- data_frame(word = unlist(text))
    #log_info('Added word variable')
    text <- text %>% 
      filter(word != '')
    #log_info('Filtered for empty')
    text <- text %>% 
      anti_join(custom_stop_words)
    #log_info('Anti-join done')
    text <- text %>% mutate(artist = artist_to_use)
    
    text_list[[i]] <- text 
  }
  
  text_list <- rbindlist(text_list)
  
  text_list <- text_list %>% count(artist, word, sort = TRUE) %>% 
    bind_tf_idf(word, artist, n) %>% group_by(word) %>% summarise(mean_tf_idf = mean(tf_idf)) %>%
    arrange(-mean_tf_idf) %>% head(20)
  
  return(text_list)
}

tf_idfer(data)

q1_data_idf <- tf_idfer(q1_data) %>% mutate(segment = 'q1') %>% head(10)

q2_data_idf <- tf_idfer(q2_data) %>% mutate(segment = 'q2') %>% head(10)

q3_data_idf <- tf_idfer(q3_data) %>% mutate(segment = 'q3') %>% head(10)

all_qs_idf <- rbindlist(list(q1_data_idf, q2_data_idf, q3_data_idf))

ggplot(all_qs_idf, aes(x = reorder(word, mean_tf_idf), mean_tf_idf, fill = segment)) +
  geom_col() +
  facet_wrap(~segment, ncol = 3, scales = 'free') +
  coord_flip()

