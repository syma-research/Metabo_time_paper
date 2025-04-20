* This repository houses the code and shareable data files from the metab-time paper (Ma et al.).

* `data/` has the pre-processing NMR profiles for the NY cohort, as well as the processed NMR, cytokine, 
  and ROS data for the NY cohort (`.RData` files). For access of patient metadata of the NY cohort, 
  contact Siyuan Ma <siyuan.ma@vumc.org>. For access of the Spanish cohort data, contact
  Óscar Millet <omillet@cicbiogune.es>

* `mds/` has the analyses scripts, including those used to generate manuscript display items. 

    * These are organized in order (data processing -> NMR O-PLS analysis and derivation of metabo-time 
      -> ROS and cytokine analyses -> nasal transcriptome analyses.

    * `R/` has utility scripts for the analyses, mainly helper functions used in the O-PLS analysis.

* `results/` has produced analyses results, including manuscript display items.
