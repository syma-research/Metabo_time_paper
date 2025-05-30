#### FUNCTIONS FOR PERFORMING OPLIS ANALYSES ####
## These were originally created by Ruben Gil-Redondo
## and further modified by Siyuan Ma.

get_lm_analysis <- function(df, grouping_var, ref_group, variables, 
                            covariant_string = "", adjust_method = "fdr") {
  df <- as.data.frame(df)
  result <- tibble(variable = variables)
  groups <- sort(unique(df[, grouping_var]))
  groups <- groups[!groups %in% ref_group]
  for (i in 1:length(groups)) {
    group_name <- groups[i]
    filter_x <- df[, grouping_var] == group_name
    filter_y <- df[, grouping_var] == ref_group
    
    this_info <- 
      map_df(result$variable, function(x) {
        this_df <- df[filter_x | filter_y, ]
        # Set correct reference level
        this_df[, grouping_var] <- factor(this_df[, grouping_var], levels = c(ref_group, group_name))        
        lm_model <- lm(paste0("`", x, "`", "~", grouping_var, 
                              covariant_string),
                       data = this_df, na.action = na.omit)
        lm_sum <- summary(lm_model)
        this_coef <- as.numeric(lm_sum$coefficients[, "Estimate"][2])
        p_value <- as.numeric(lm_sum$coefficients[, "Pr(>|t|)"][2])
        se <- as.numeric(lm_sum$coefficients[, "Std. Error"][2])
        confint_95_low <- confint(lm_model)[2, 1]
        confint_95_high <- confint(lm_model)[2, 2]
        sd_ref_group <- sd(df[filter_y, x], na.rm = T)
        
        # Convert to SD units
        this_coef <- this_coef / sd_ref_group
        se <- se /sd_ref_group
        confint_95_low <- confint_95_low / sd_ref_group
        confint_95_high <- confint_95_high / sd_ref_group
        
        this_info <- data.frame(
          sd_coef = this_coef, 
          p_value = p_value, 
          sd_se = se,
          sd_confint_95_low = confint_95_low,
          sd_confint_95_high = confint_95_high,
          sd_ref_group = sd_ref_group
        )
        return(this_info)
      }) 
    if (!is.na(adjust_method)) {
      this_info$p_value <- p.adjust(this_info$p_value, method = adjust_method)
    }
    names(this_info) <- paste0(group_name, ".vs.", ref_group, ".", names(this_info))
    result <- bind_cols(result, this_info)
  }
  
  return(result)
}


filter_variables <- function(univ_df, min_effect = 0.5, max_pval = 0.05,
                             max_corr = NULL, this_data = NULL) {
  
  univ_df <-
    univ_df %>%
    filter(abs(effect) >= min_effect & pvalue < max_pval) %>%
    as.data.frame()
  
  var_names <- univ_df$variable
  selected_vars <- var_names
  
  # Remove higlhy correlated if required
  if (!is.null(max_corr) & !is.null(this_data)) {
    repeat {
      descrCor <- cor(this_data[, selected_vars])
      diag(descrCor) <- NA
      this_max_corr <- max(descrCor, na.rm = T)
      if (this_max_corr < max_corr) {
        break
      }
      competitors <- selected_vars[which(descrCor == max(descrCor, na.rm = T), 
                                         arr.ind = TRUE)[1, ]]
      
      to_keep <- filter(univ_df, variable %in% competitors) %>% arrange(desc(abs(effect))) %>% slice(1) %>% pull(variable)
      to_remove <- competitors[!competitors %in% to_keep]
      
      selected_vars <- selected_vars[selected_vars != to_remove]
    }
  }
  
  return(selected_vars)
}


do_cv <- function(X, Y, k = 5, repeats = 10) {
  
  result <- tibble()
  
  for (j in 1:repeats) {
    
    #cat(paste0("Repetition ", j, "\n"))
    
    # Create folds
    my_folds <- caret::createFolds(Y, k)
    
    for (i in 1:k) {
      test_ids <- my_folds[[i]]
      x_train <- X[-test_ids, ]
      y_train <- Y[-test_ids]
      x_test <- X[test_ids, ]
      y_test <- Y[test_ids]  
      
      this_model <-
        suppressMessages(opls(X = x_train, 
                              Y = y_train,
                              center = T,
                              scale = "UV",
                              maxPCo = 2,
                              cv = list(method = "k-fold", k = 2, split = 2/3), plotting = F))
      
      this_roc <- suppressMessages(pROC::roc(y_train, as.numeric(this_model@t_pred)))
      this_auc <- as.numeric(this_roc$auc)
      this_id_threshold <- which.max(this_roc$sensitivities+this_roc$specificities)[1]
      this_sen <- this_roc$sensitivities[this_id_threshold]
      this_spe <- this_roc$specificities[this_id_threshold]
      result <- 
        result %>%
        bind_rows(
          tibble(
            repetition = j, type = "train", auc = this_auc, sen = this_sen, spe = this_spe
          )
        )
      
      this_roc <- suppressMessages(pROC::roc(y_test, as.numeric(as.numeric(predict_opls(this_model, newdata = x_test)$t_pred[, 1]))))
      this_auc <- as.numeric(this_roc$auc)
      this_id_threshold <- which.max(this_roc$sensitivities+this_roc$specificities)[1]
      this_sen <- this_roc$sensitivities[this_id_threshold]
      this_spe <- this_roc$specificities[this_id_threshold]
      result <- 
        result %>%
        bind_rows(
          tibble(
            repetition = j, type = "test", auc = this_auc, sen = this_sen, spe = this_spe
          )
        )
      
    }
  }
  
  return(result)
}


get_pvalue_metrics <- function(useX, useY, ref_auc, ref_sen, ref_spe, with_cv = T, max_iter = 10, use_k = 5, use_repeats = 10) {
  num_auc <- 0
  num_sen <- 0
  num_spe <- 0
  
  perm_metrics <- tibble()
  
  for (i in 1:max_iter) {
    
    cat(paste0("Permutation ", i, "\n"))
    
    if (with_cv) {
      this_result <- do_cv(useX, sample(useY, length(useY)), k = use_k, repeats = use_repeats)
      this_result <-
        this_result %>%
        filter(type == "test") %>%
        summarise(across(.cols = c("auc", "sen", "spe"), .fns = mean))
    } else {
      this_Y <- sample(useY, length(useY))
      this_model <-
        suppressMessages(opls(X = useX, 
                              Y = this_Y,
                              center = T,
                              scale = "UV",
                              maxPCo = 2,
                              cv = list(method = "k-fold", k = 2, split = 2/3), plotting = F))
      
      this_roc <- suppressMessages(pROC::roc(this_Y, as.numeric(as.numeric(predict_opls(this_model, newdata = useX)$t_pred[, 1]))))
      this_auc <- as.numeric(this_roc$auc)
      this_id_threshold <- which.max(this_roc$sensitivities+this_roc$specificities)[1]
      this_sen <- this_roc$sensitivities[this_id_threshold]
      this_spe <- this_roc$specificities[this_id_threshold]
      this_result <- tibble(auc = this_auc, sen = this_sen, spe = this_spe)
    }
    
    perm_metrics <-
      perm_metrics %>%
      bind_rows(this_result)
    
    if (this_result$auc > ref_auc) num_auc <- num_auc + 1
    if (this_result$sen > ref_sen) num_sen <- num_sen + 1
    if (this_result$spe > ref_spe) num_spe <- num_spe + 1
  }
  
  return(
    list(
      pvalues = tibble(
        auc_pvalue = ifelse(num_auc == 0, paste0("<", 1/max_iter), as.character(num_auc / max_iter)),
        sen_pvalue = ifelse(num_sen == 0, paste0("<", 1/max_iter), as.character(num_sen / max_iter)),
        spe_pvalue = ifelse(num_spe == 0, paste0("<", 1/max_iter), as.character(num_spe / max_iter)),
      ),
      perm_metrics = perm_metrics
    )
  )
}
