################################################################################
# 
#   Logistic Regression
#
################################################################################
# Description:
#  - creates log regression baseline model
#  - N-fold crossvaliadation
#  - variable selection via mix of filtering & wrappers
################################################################################

rm(list = ls())

# Adjust your working directory
wd = file.path(Sys.getenv("HOME"),"/Documents/Projects/bads-ws1718-group21")
setwd(wd)

load("Data/BADS_WS1718_known_var.RData")

library(caret)
library(hmeasure)
library(InformationValue)
library(mlr)
library(klaR)

# Create partition
set.seed(321)
Trainp <- createDataPartition(y = dat.input$return, p = 0.7, list = FALSE)
Test <-  dat.input[-Trainp, ] 
Train <- dat.input[Trainp, ]
# Preliminary filtering: Remove not useful variables

vec.remove <- c("order_date", "delivery_date",
                 "user_dob",
               "user_reg_date", "user_dob_year", "WOE.brand",
               "WOE.size", "aver.return.item", "WOE.item",
                "order_year", "aver.return.brand", "no.return")

idx.remove <- which(colnames(Train) %in% vec.remove)

Train <- Train[,-idx.remove]

################################################################################
################################################################################

# Filtering based on Fisher score (continous) ) 
# and information value (categorical)

### Fisher Score

Score.fisher <- function(var, target){
        classMeans <- tapply(var, target, mean)
        classStds <- tapply(var, target, sd)
        classDiff <- abs(diff(classMeans))
        coefficient <- as.numeric(classDiff / sqrt(sum(classStds^2)))
    return(coefficient)
}

# Extract fisher score for all categorical variables
Scores.fisher <- apply(Train[,sapply(Train, is.numeric)], 
                       2, Score.fisher, Train$return)

Scores.fisher[order(Scores.fisher)]

# Todo: remove continous variables based on Fisher score (define rule)

################################################################################

### Information value based on WOE

woe.scores <- woe(return ~ ., data = Train, zeroadj = 1)
woe.scores$IV

# Create new Train and Test data set including woe
Train1 <- cbind(return = dat.input1$return, woe.scores$xnew)
Test1 <- predict(woe.scores, newdata = Test, replace = TRUE)

# Index for variables to be removed
idx.remove.woe <- which(colnames(Train1) %in% 
                       paste0("woe.", names(which(woe.scores$IV < 0.02))))

# Remove variables with low IV
Train1 <- Train1[,-idx.remove.woe]
###########
# Optionally if dont continoue with new woe data set
# Remove variables with too many levels
idx.factor <- c("item_id", "item_size", "item_color")
idx.factor <- which(colnames(Train) %in% idx.factor)
Train <- Train[, -idx.factor]
###########

# Baseline Logistic regression
logReg <- glm(return ~., 
               data = Train1, family = binomial(link = "logit"))

summary(logReg)

# Wrapper: Sequential floating backward selection (SFBS)

task <- makeClassifTask(data = Train1, target = "return", positive = "1")
lr <- makeLearner("classif.logreg", 
                  predict.type = "prob")
# Set up feature selection control object.

# Sequential forward selection
featureSearchCtrl <- makeFeatSelControlSequential(method = "sbs",
                                                  alpha = 0.01)
# Set up resampling as before
rdesc <- makeResampleDesc(method = "CV", iters = 3, stratify = TRUE)

# Run the feature selection function (similar to the parameter tuning function)
featureSelection <- selectFeatures(lr, task = task, resampling = rdesc,
                                   control = featureSearchCtrl, measures = mlr::auc,
                                   show.info = TRUE)

# Number of variables in total
ncol(task$env$data)
# Variables selected by random forest wrapper using treshold alpha
featureSelection

# Construct index for final data set 
idx.keep.wrapper <- c(which(colnames(Train) %in% featureSelection$x), 
                      which(colnames(Train) == "return"))

Train <- Train[,idx.keep.wrapper ]

# Make final estimation and prediction
logReg4 <- glm(return ~. , 
              data = Train.final, family = binomial(link = "logit"))

estimates <- list()

estimates <- predict(logReg4, newdata = Test2, type = "response", 
                                 replace = TRUE)


# Check out model performance 
estimates.df <- data.frame(estimates)  
AUC <- HMeasure(as.numeric(Test2$return)-1, estimates.df) 
auc_logReg4 <- AUC$metrics['AUC']
auc_logReg4

pred = data.frame(cbind(Test2$return, estimates.df$estimates))
pred$X3 = ifelse(pred$X2>0.5, 2,1)
pred$X4 = abs(pred$X1-pred$X3)
pred$X5 = pred$X1-1
pred$X6 = pred$X3-1

misClassError(pred$X5, pred$X6)
estimates$logReg = ifelse(Test$no.return == 1, 0, estimates$logReg)

sensitivity(Test$return, estimates$logReg, threshold = 0.5)
specificity(Test$return, estimates$logReg, threshold = 0.5)

plotROC(Test$return, estimates$logReg)

BrierScore <- function(y, predicted){
    sum((y - predicted)^2) / length(y)}

BrierScore(Test$return, estimates$logReg)

# Determine optimal cutoff threshold
optimalCutoff(actuals = Test$return, predictedScores = estimates$logReg, 
              optimiseFor = "Zeros")


