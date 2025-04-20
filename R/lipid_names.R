df_lipid_mapping <- readr::read_csv("data/lipid_names.csv") %>% 
  dplyr::mutate(variable_print = dplyr::case_when(
    Main_sub == "Sub" ~ paste0(Parameter, " (", Fraction, "-", stringr::str_extract(Key, "[0-9]"), ")"),
    Main_sub == "Main" ~ paste0(Parameter, " (", Fraction, ")"),
    TRUE ~ Parameter
  )) 
