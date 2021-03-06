# collection of functions that assist with analyzing 
# data from model runs after theyve been consolidated
# March 2019 - March 2020


## FILE STRUCTURE ##
# base_fol = "/Users/patricia/Documents/Google Drive/stanford/Value of DR Project/"
# output_fol_base = "Data/julia_output/forIAEE_1PMin/"
# input_fol = "Data/julia_input/"

## RESOURCES ##
library(tidyverse)
library(viridis) # for nicer plot colors
library(data.table) # for faster merges
library(lubridate)
# source(paste0(base_fol,"/Julia_UC_Github/R_Scripts/mergeTimeseriesData.R")) # contains loadTimeseriesData
## 

baseFol = "~/dr_stoch_uc/"
outputFolBase = "/home/groups/weyant/plevi_outputs/"
inputFol = "inputs/"
scriptsFol = "code/"
source(paste0(baseFol,"code/R_Scripts/mergeTimeseriesData.R")) # contains loadTimeseriesData()


# costByTimestep(runID, runDate, instance_in_fol, default_in_fol)
costByTimestep = function(runID, runDate,  
                          instanceFol,# e.g. "/home/users/pjlevi/dr_stoch_uc/julia_ver/inputs/5d_6o_keyDays2/" (instance_in_fol)
                          default_in_fol,  # e.g. "/home/users/pjlevi/dr_stoch_uc/julia_ver/inputs/ercot_default/"
                          scripts_fol = scriptsFol, # e.g. "code/"
                          outputBase = outputFolBase # e.g. "/home/groups/weyant/plevi_outputs/"
                          ){
  # set up file paths
  outputfolID  = paste0(runID,"_",runDate)
  output_fol = paste0(outputBase,outputfolID,"/")
  if(!SHRLK){
    inputs_file = paste0(base_fol,scripts_fol,"inputs_ercot.csv")
  }else{
    inputs_file = paste0(base_fol,scripts_fol,"inputs_ercot.csv")
  }
    
  # get params
  allinputs = read_csv(inputs_file)
  params = allinputs[,c("input_name",runID)]
  params = spread(params, key = input_name, value = runID)

  # load prod
  prod = read_csv(file = paste0(output_fol,"prod.csv"))
  
  # load commit data
  allstart = loadTimeseriesData(output_fol,"v_startup",as.numeric(params$overlapLength),2, probabilities=F,instanceFol,
                               params$nrandp,dist_ID = params$stochID,endtrim=as.numeric(params$overlapLength)/2)
  # handle allstart data
  allstart$value = round(allstart$value) #numerical errors
  allstart$value[allstart$value < 0] = 0 # we only care about the cost of starting up
  
  # load generator data
  gendat = read_csv(file = paste0(default_in_fol,params$genFile))
  gendat = dplyr::rename(gendat, GEN_IND = plantUnique)

   # load list of slow gens, add slow/fast spec to gendat
  slowgens = read_csv(file = paste0(output_fol,"slow_gens.csv"))
  slowgens = slowgens$x
  speedslow = tibble(GEN_IND = slowgens, speed = "slow")
  gendat = merge(gendat, speedslow, by = "GEN_IND", all.x=T)
  gendat$speed[is.na(gendat$speed)]="fast"
       ## Somehow including this messes up the merge later...!
        ## so fast generators are NA for speed in commitment
  
  # # merge gendat with prod
  prod2 = merge(as.data.table(prod), as.data.table(gendat[,c("GEN_IND","VCost","StartCost","Fuel")]), by = "GEN_IND", all.x=T)

  # merge gen with commit
  start2 = merge(as.data.table(allstart), as.data.table(gendat[,c("GEN_IND","VCost","StartCost","Fuel","speed")]), by = "GEN_IND", all.x=T) 
  start2 = rename(start2, startup = value)

  # calculate $/prod, $/commit
  prod2$prodcost = as.numeric(prod2$MWout) * as.numeric(prod2$VCost)
  start2$startcost = as.numeric(start2$startup) * as.numeric(start2$StartCost)
  
  # summarise cost by t, scenario
  prod3 = prod2 %>%
    group_by(t, scenario, nperiod)  %>%  ##speed
    summarise(totprodcost = sum(prodcost,na.rm=T))
  start3 = start2 %>%
    group_by(t, scenario, nperiod)  %>% ##speed
    summarise(totstartcost = sum(startcost,na.rm=T))
  
  # merge prod, commit, add up
  allcost = merge(as.data.frame(prod3),as.data.frame(start3), by = c("t","scenario","nperiod"), all.x=T, all.y=T) ##speed
 
  # calculate summary stats for $/t across scenarios
  # replace NAs with 0
  allcost$totprodcost[is.na(allcost$totprodcost)] = 0
  allcost$totstartcost[is.na(allcost$totstartcost)] = 0
  
  # compute sum across scenarios
  allcost$totcost  = allcost$totprodcost + allcost$totstartcost
  allcost2 = allcost %>%
    group_by(t) %>% # can also group by nperiod to retain this variable without changing anything
    summarize(meanprodcost = mean(totprodcost),
                     meanstartcost = mean(totstartcost),
              meancost = mean(totcost),
              maxcost = max(totcost),
              mincost =  min(totcost),
              sdcost = sd(totcost)) 

  # for plotting
  allcost2$rankt = rank(allcost2$t)
  
  # make plot?
  plot_fol = paste0(output_fol,"plots/")
  if(!dir.exists(plot_fol)){dir.create(plot_fol)}
  
  # Identify breaks between runs
  jumps = which(diff(allcost2$t)>1)

  ggplot(allcost2, aes(x = rankt, y = meancost)) +
    geom_line()+
    geom_line(aes(x=rankt,  y = mincost, color = "light blue")) + 
    geom_line(aes(x=rankt,  y = maxcost, color = "light green")) +             
    theme_minimal() +
    geom_vline(xintercept = jumps+0.5, color = "red", linetype="dotted")+
    scale_color_discrete(name = "", labels = c("Min","Max"))
    ggsave(paste0(plot_fol,runID,"_totcost.png"), width = 20, height = 5)
  
  # save dataframe
  write_csv(path =  paste0(plot_fol,runID,"_totcost.csv"), allcost2)
  
  # save csv of cost by scenario
  write_csv(path =  paste0(plot_fol,runID,"_allcost.csv"), allcost)
  
  # jumps = which(diff(allcost$t)>1)
  allcost$rankt = rank(allcost$t)
  
  ggplot(allcost, aes(x = rankt, y = totcost, color = scenario)) +
    facet_wrap(~nperiod, scales="free_x")+
    geom_line() + theme_minimal() +
    ggsave(paste0(plot_fol, runID,"_allcost.png"),width = 20, height = 20)
    
}



eventStats = function(runID, runDate, output_fol_base = outputFolBase){
  # depends on getDRAllData
  # based on that output, computes:
  # - number of unique events in each scenario
  # - length of each event
  # - start time of each event (probably requires lubridate)
  # and plots
  # - histogram of event length
  # - histogram of event start time
  # - histogram of number of events across all scenarios  (eg total count  is 25)
  
## param setup
  outputfolID = paste0(runID,"_",runDate)
  output_fol = paste0(output_fol_base,outputfolID,"/")
  plot_fol = paste0(output_fol_base,"plots/")
  if(!dir.exists(plot_fol)){dir.create(plot_fol)}
  
  # load DR all data
  drdat = getDRAllData(runID,runDate)
  
## Find events and assign ID, based off of code below:
      # prodtimes =  arrange(filter(drdat,value.commit>0, scenario == "o1"), t)
      # jumps = which(diff(prodtimes$t)>1)
      # prodtimes$diff  = c(0,diff(prodtimes$t)) #assume t sorted
      # prodtimes$end = -1 #if  any -1 remain,  error. also logic is broken.
      # prodtimes$end[prodtimes$diff == 1] = 0
      # prodtimes$end[prodtimes$diff != 1] = 1
      # # prodtimes$end3  = !(c(0,diff(prodtimes$t)) == 1) #this is just the oneliner of  the previous three lines to see if  I could... but it is harder to read
      # prodtimes$eventnum  = cumsum(prodtimes$end)
  drdat$scenarionum = as.numeric(drdat$scenarionum)
  drdat2 = drdat %>%
    filter(value.commit >0) %>%
    arrange(scenarionum,t)
  # scenarios are in order
  # t is strictly increasing except when we swich to next scenario
  drdat2$tdiffs = c(0,diff(drdat2$t))
 
  drdat2$eventStart = -1
  drdat2$eventStart[drdat2$tdiffs == 1] = 0
  drdat2$eventStart[drdat2$tdiffs != 1] = 1
  drdat2$eventnum = cumsum(drdat2$eventStart)
  
## count number of events in each scenario  &  plot ##
  eventdat = drdat2 %>%
    group_by(scenario,scenarionum) %>%
    summarise(nevents = length(unique(eventnum)))
    ggplot(eventdat,aes(x = nevents)) + theme_minimal() +
      geom_histogram(binwidth = 1,color = "black", fill = "light grey") +
      labs(title = paste("Distribution of number events across scenarios",runID),
           x = "Number of DR events in scenario",
           y = "number of scenarios") +
      coord_cartesian(xlim  = c(10,75)) +
      ggsave(paste0(plot_fol,"eventNum_hist_",runID,"_",runDate,".png"), width = 6, height = 5)
## identify length of each event and plot ##
  eventlength = drdat2 %>%
    group_by(eventnum, scenarionum) %>% 
    summarise(length = n())
  
  #  all together
  p = ggplot(eventlength, aes(x = length)) +
    geom_histogram(binwidth = 1,color = "black", fill = "light grey") + 
    theme_minimal() +
    coord_cartesian(xlim=c(0,14))+
    labs(x = "Duration of DR event (hours)", y = "Number of events",
         title = paste("Distribution of event length across all scenarios",runID))
  
  p + 
    ggsave(paste0(plot_fol,"eventLength_hist_",runID,"_",runDate,".png"), width = 6, height = 5)
  
  # faceted by scenario
  p + labs(title = paste("Distribution of event length by scenario",runID)) +
    facet_wrap(~scenarionum, nrow = 5) + 
    theme_bw()+
    coord_cartesian(xlim=c(0,14))+
    ggsave(paste0(plot_fol,"eventLength_byScenario_hist_",runID,"_",runDate,".png"), width = 10, height = 8)
  
## identify start time of each event ##
    # convert T to an hour of the day  (maybe also day of week?)
    # summarise & plot
  first_hour = ymd_hm("2016-01-01 00:00")
  drdat2$datetime = first_hour + hours(drdat2$t -1) #TODO:IS T 0-INDEXED OR 1 INDEXED?
  drdat2$hour = hour(drdat2$datetime)
  
  drdat_starthours = filter(drdat2, eventStart==1)
  ggplot(drdat_starthours,aes(x=hour)) +
    geom_histogram(breaks = seq(-0.5,25.5, by = 1), color = "black", fill = "light grey") + theme_minimal() +
    labs(x = "hour of the day", y = "number of events",
         title = paste("Distribution of initial hour of events",runID)) +
    coord_cartesian(xlim = c(0,24)) +
    ggsave(paste0(plot_fol,"event_startHour_hist_",runID,"_",runDate,".png"), width = 6, height = 5)
  
  ggplot(drdat2, aes(x=hour)) +
    geom_histogram(breaks = seq(-0.5,25.5, by = 1),color = "black", fill = "light grey") + 
    theme_minimal() +
    labs(x = "hour of the day", y = "number of events",
         title = paste("Distribution of hours when DR is on",runID))+
    coord_cartesian(xlim = c(0,24)) +
    ggsave(paste0(plot_fol,"event_dispatchedHours_hist_",runID,"_",runDate,".png"), width = 6, height = 5)
  
  
  # TODO: create a DF of output data
  # save output DF somewhere
  
}


# getDRAllData
# Return a dataframe containing all  DR commitment and dispatch info
# names of returned dataframe are:
# [1] "t"            "scenario"     "nperiod"      "GEN_IND"      "value.commit"
# [6] "DR_IND"       "value.prod" 
    # to run - 
    # runID = "advNot3_o25_keyDays2"
    # runDate  = "2019-12-12"
    # getDRAllData(runID,runDate)
getDRAllData = function(runID, runDate, 
                        inputfolID =  "5d_6o_keyDays2", 
                        base_fol = baseFol, input_fol = inputFol, 
                        output_fol_base = outputFolBase, savecsv=FALSE){
  
  outputfolID = paste0(runID,"_",runDate)
  
  # load params
  instance_in_fol = paste0(base_fol,input_fol,inputfolID,"/")
  if(!dir.exists(instance_in_fol)){stop("julia input file doesnt exist ", instance_in_fol)}
  output_fol = paste0(output_fol_base,outputfolID,"/")
  
  if(!SHRLK){
    inputs_file = paste0(base_fol,"/Julia_UC_Github/Julia_scripts/inputs_ercot.csv")
  }else{
    inputs_file = paste0(base_fol,"/code/inputs_ercot.csv")
  }
  allinputs = read_csv(inputs_file)
  params = allinputs[,c("input_name",runID)]
  params = spread(params, key = input_name, value = runID)
  endtrim = as.numeric(params$overlapLength)/2
  
  # load commitment and  production data
  allcomt = loadTimeseriesData(output_fol,"u_commitment",as.numeric(params$overlapLength),2, probabilities=F,instance_in_fol,
                               params$nrandp,dist_ID = params$stochID,endtrim)
  drcomt = filter(allcomt,str_detect(GEN_IND,"DR-"))
  rm(allcomt)
  
  drprod = loadTimeseriesData(output_fol,"DR_production",as.numeric(params$overlapLength),2, probabilities=F,instance_in_fol,
                              params$nrandp,dist_ID = params$stochID, endtrim)
  
  # combine &  generate scenarionum  for convenience
  dralldata = merge(drcomt, drprod, by=c("t","scenario","nperiod"), suffixes = c(".commit",".prod"))
  dralldata$scenarionum = as.numeric(substr(dralldata$scenario,2,4))

  # save
  if(savecsv){
    write_csv(dralldata, paste0(output_fol,runID,"_",runDate,"_dralldata.csv"))
  }
  
  return(dralldata)
}

getCO2data = function(runID,runDate, 
                      inputfolID =  "5d_6o_keyDays2", 
                      base_fol = baseFol, input_fol = inputFol, 
                      output_fol_base = outputFolBase, savecsv=FALSE){
 #setup and params
  outputfolID = paste0(runID,"_",runDate)
  # load params
  instance_in_fol = paste0(base_fol,input_fol,inputfolID,"/")
  if(!dir.exists(instance_in_fol)){stop("julia input file doesnt exist ", instance_in_fol)}
  output_fol = paste0(output_fol_base,outputfolID,"/")
  if(!SHRLK){
    inputs_file = paste0(base_fol,"/Julia_UC_Github/Julia_scripts/inputs_ercot.csv")
  }else{
    inputs_file = paste0(base_fol,"/code/inputs_ercot.csv")
  }
  allinputs = read_csv(inputs_file)
  params = allinputs[,c("input_name",runID)]
  params = spread(params, key = input_name, value = runID)
  endtrim = as.numeric(params$overlapLength)/2
  
  # load production data
  prod = read_csv(file = paste0(output_fol,"prod.csv"))
  
  # load generator data
  gendat = read_csv(file = paste0(base_fol,input_fol,"ercot_default/",params$genFile))
  # PLC2ERTA in generator data has units of lb/MWh
  noco2 = which(is.na(gendat$PLC2ERTA))
  for(i in 1:length(noco2)){
    fueltype = gendat$Fuel[noco2[i]]
    meanco2 = mean(gendat$PLC2ERTA[gendat$Fuel == fueltype],na.rm=T)
    if(is.na(meanco2)){
      print(paste0("Mean co2 emissions not identified for ", gendat$plantUnique[noco2[i]]))
      meanco2 = 0
    }
    print(paste0("CO2 intensity for ", gendat$plantUnique[noco2[i]]," set to ", meanco2))
    gendat$PLC2ERTA[noco2[i]] = meanco2
  }

  # merge gendat with prod
  prod2 = merge(prod,gendat,by.x="GEN_IND",by.y = "plantUnique")
  
  prod3 = prod2 %>%
    mutate(co2emit = PLC2ERTA*MWout) %>%
    group_by(Fuel,t,scenario) %>%
    summarise(co2 =  sum(co2emit))
  
  if(savecsv){
    write_csv(prod3, paste0(output_fol,runID,"_",runDate,"_co2data.csv"))
  }
  
  return(prod3)
}

plotCO2 = function(runID,runDate){
  #plot of CO2 emissions by  generator type for a given run
  
}

plotallCO2 = function(folder,searchString,saveas  = "all_co2_boxplot",
                      fast_gens = c("GAS_CT","GAS_ICE","OIL","SOLAR","WIND","HYDRO"),
                      plots = F){
  # plot of CO2 emissions across all runs
  # each run is represented by a boxplot showing range of emissions across scenarioss
  xx = list.files(path = folder, pattern = glob2rx(searchString))
  runIDs = substr(xx, 1, nchar(xx)-11)
  runDates = substr(xx, nchar(xx)-9,100)
  
  plot_fol =  paste0(folder,"plots/")
  if(!dir.exists(plot_fol)){dir.create(plot_fol)}
  
  
  #get all CO2 data
  for(i in 1:length(xx)){
    filename = paste0(folder,runIDs[i],"_",runDates[i],"/",runIDs[i],"_",runDates[i],"_co2data.csv")
    if(file.exists(filename)){
      print(paste("loading",filename))
      co2emit = read.csv(filename)
    } else {
      print(paste("creating", filename))
      co2emit = getCO2data(runIDs[i],runDates[i],output_fol_base = folder, savecsv = TRUE)
    }
     
    co2_intermediate = co2emit %>%
      group_by(Fuel,scenario) %>%
      summarise(co2tot = sum(co2))
    co2_intermediate$run = xx[i]
    co2_intermediate$speed = "slow"
    for(s in 1:length(fast_gens)){
        fast_ind = str_detect(as.character(co2_intermediate$Fuel),pattern = fast_gens[s])
        co2_intermediate$speed[fast_ind] = "fast"
    }

    # for plotting co2 emissions by fuel type
    co2emit_sum = co2_intermediate %>%
      group_by(Fuel) %>%
      summarise(co2mean = mean(co2tot),
                co2min = min(co2tot),
                co2max = max(co2tot))
    co2emit_sum$run = xx[i]
    
    # for total plot
    co2emit2 = co2emit %>%
      group_by(scenario) %>%
      summarise(allco2emit = sum(co2))
    co2emit2$run = xx[i]
    
    if(i==1){
      allco2 = co2emit2
      allco2_byspd = co2_intermediate
    } else {
      allco2 = rbind(allco2,co2emit2)
      allco2_byspd = rbind(allco2_byspd,co2_intermediate)
    }

   # make a plot of co2 emissions by fuel  type
    if(plots){
    ggplot(co2emit_sum,aes(x=Fuel,y=co2mean)) + 
      theme(axis.text.x =  element_text(angle=90,hjust=1)) +
      geom_errorbar(aes(ymin = co2min,  ymax = co2max), color = "grey") +
      geom_point() + theme_minimal() +
      geom_text(aes(label = round(co2mean,0)),size = 2,vjust=-1, angle = 15) +
      labs(title  = paste("CO2 emissions  by generator type,",runIDs[i],"\n error bars give range across scenarios"),
           y = "Tons CO2 emitted") +
      ggsave(paste0(plot_fol,runIDs[i],"_",runDates[i],"co2_by_fueltype.png"),width = 8,height=6)
    }
  }
  
  # for comparison with combined_summary file
  co2_speed = allco2_byspd %>%
    group_by(speed, run, scenario) %>% # lose the Fuel dimension
    summarise(totco2 = sum(co2tot)) %>%
    group_by(speed, run) %>%
    summarise(co2mean = mean(totco2),
              co2min = min(totco2),
              co2max = max(totco2))
  
  # plot
if(plots){
 ggplot(allco2,aes(x =  run, y = allco2emit)) + geom_boxplot() +
   theme_minimal()+
   theme(axis.text.x =  element_text(angle=90,hjust=1))+
   ggsave(paste0(plot_fol,saveas,".png"),width = 12, height=9)
}
 return(co2_speed)
}
# to test:
# source("./consolidatedAnalysisFns.R")
# plotallCO2(folder = "/home/groups/weyant/plevi_outputs/", searchString = "*_o25*keyDays2*")
# co2_wide = pivot_wider(co2,names_from = "speed", values_from = c("co2mean","co2min","co2max"))
#  write_csv(co2_wide, path = "/home/groups/weyant/plevi_outputs/co2_byspeed_wide_05-01.csv")


## Plot DR Production ####
#TODO: add ability to plot multiple periods together
#TODO: have demand, vdem be inputs

# from Nov 20, 2019 commit -  ie before  I tried to edit plotDRUse to plot all periods at once
# just plots one period
plotDRUse = function(runID,runDate,drcommit,
                     inputfolID, outputfolID,
                     scenarios = 1:10, # what scenarios will be graphed
                     overlaplength = 6, endtrim = NULL,#loadTimeseriesData param
                     period = "p10_5238_5340", nscen = "o25",
                     model_output_fol = outputFolBase, 
                     model_input_fol = inputFol,
                     SHRLOK = SHRLK,
                     base_fol = baseFol) { 
  # model_output_fol is where model output folder : 
  # instance_in_fol is where model input is
  # plot_fol is where plots should go
  # output_fol: paste0(base_fol,output_fol_base,outputID,"/")
  # plot_fol:   paste0(base_fol,output_fol_base,"plots/")
  # instance_in:paste0(base_fol,input_fol,inputfolID,"/")
  
  plot_fol = paste0(model_output_fol,"plots/")
  if(!dir.exists(plot_fol)){dir.create(plot_fol)}
  
  instance_in_fol = paste0(baseFol,model_input_fol,inputfolID,"/")
  if(!dir.exists(instance_in_fol)){stop("julia input file doesnt exist ", instance_in_fol)}
  output_fol = paste0(model_output_fol,outputfolID,"/")
  
  # load params
  if(!SHRLK){
    inputs_file = paste0(base_fol,"/Julia_UC_Github/Julia_scripts/inputs_ercot.csv")
  }else{
    inputs_file = paste0(base_fol,"/code/inputs_ercot.csv")
  }
  allinputs = read_csv(inputs_file)
  params = allinputs[,c("input_name",runID)]
  params = spread(params, key = input_name, value = runID)
  
  if(is.null(endtrim)){
    endtrim = overlaplength/2
    print(paste("endtrim set to", endtrim))
  }
  
  ## load drdat
  drdatfile = paste0(output_fol,outputfolID,"_dralldata.csv")
 
  if(file.exists(drdatfile)){
    drdat = read_csv(drdatfile)
  } else if(!str_detect(outputfolID,"noDR")) {
    drdat = getDRAllData(runID, runDate, output_fol_base = output_fol, savecsv = TRUE)
  } else {
    # this is a noDR file
    return()
  }
  
  # ID key stats about the period we are asked to graph
  periodinfo = strsplit(period,"p|_")[[1]] 
  numperiod=as.numeric(periodinfo[2])
  firstperiod = as.numeric(periodinfo[3])
  lastperiod = as.numeric(periodinfo[4])
  # load and set up demand #
  dem_base = read_csv(paste0(base_fol,model_input_fol,"ercot_default/ercot_demand_2016.csv"))
  demchange = read_csv(paste0(instance_in_fol,"demandScenarios_vdem_ARMA26.0_",nscen,"_",period,".csv")) 
  demrealo1 = dem_base$demand[firstperiod:lastperiod] * demchange$V1
  demreal = dem_base$demand[firstperiod:lastperiod] * demchange
  demreal$t = firstperiod:lastperiod
  demrealwide = demreal
  demreal = gather(demrealwide,key = "scenario",value = "demand",-t) 
  demreal$scenarionum = substr(demreal$scenario,2,4)
  
  # select demand from just one period #
  droneperiod = filter(drdat,nperiod == numperiod)
  # droneperiod$scenarionum = substr(droneperiod$scenario,2,4)
  alldat = merge(demreal,droneperiod,by=c("t","scenarionum")) 
  
  # plot demand and DR production
  ggplot(filter(alldat,scenarionum %in% scenarios))+ 
    facet_wrap(~scenario.x) + 
    geom_line(aes(x=t-min(t), y=(value.prod*10)+30000), color="blue")+
    geom_line(aes(x=t-min(t),y=demand)) +
    # scale_color_gradient(low="black",high="red")+
    ggtitle(paste(runIDs[r], "Period ",numperiod," demand and DR Production")) +
    ggsave(paste0(plot_fol,runIDs[r],"_",period,"_demand_DRproduction.png"),width = 10, height=7)
  
  # plot dr commitment
   ggplot(filter(alldat,scenarionum %in% scenarios))+ 
    facet_wrap(~scenario.x) + 
    geom_line(aes(x=t-min(t), y=(value.commit*10000)+30000), color="blue")+
    geom_line(aes(x=t-min(t),y=demand)) +
    # scale_color_gradient(low="black",high="red")+
    ggtitle(paste(runIDs[r], paste("Period",numperiod,"demand and DR Commitment"))) +
    ggsave(paste0(plot_fol,runIDs[r],"_",period,"_demand_DRcommitment.png"),width = 10, height=7)
  
  # plot both together
  ggplot(filter(alldat,scenarionum %in% scenarios))+ 
    facet_wrap(~scenario.x) + 
    geom_line(aes(x=t-min(t), y=(value.prod*10)+30000), color="blue")+
    geom_point(aes(x=t-min(t), y=(value.prod*10)+30000, color = value.commit), shape=1, size = 0.5) + 
    geom_line(aes(x=t-min(t),y=demand)) +
    scale_color_gradient(low="black",high="red")+
    ggtitle(paste(runIDs[r], paste("Period",numperiod,"demand and DR production with commitment in red"))) +
    ggsave(paste0(plot_fol,runIDs[r],"_",period,"_demand_DRfunction.png"),width = 10, height=7)
  
  
  ### Summarise all scenarios togetether ###
  scenmean = alldat %>%
    group_by(t) %>%
    dplyr::summarise(p_commit = mean(value.commit),
              mean_prod = mean(value.prod),
              max_prod = max(value.prod),
              min_prod = min(value.prod))
  # add demand back in
  scenmean = merge(scenmean, demrealwide, by="t")
  demreal$scenarionum  = as.factor(demreal$scenarionum)
  
  dp = ggplot(demreal) + geom_line(aes(x=t-min(t),y=demand, color=scenarionum))
  dp + ggsave(paste0(plot_fol,period,"_demand.png"),width = 10, height=7)
  
  
  dr = ggplot(scenmean) +
    geom_line(aes(x=t-min(t), y=mean_prod), color="blue")+
    geom_line(aes(x=t-min(t), y = min_prod), color = "light blue")+
    geom_line(aes(x=t-min(t), y = max_prod), color = "light blue")+
    coord_cartesian(ylim =c(0,1000)) +
    geom_point(aes(x=t-min(t), y=mean_prod, color = p_commit), shape=1, size = 0.5) + 
    scale_color_gradient(low="black",high="red")+
    ggtitle(paste(runIDs[r], paste("Period",numperiod,"mean/min/max DR production with mean commitment in red"))) #+
  dr +  ggsave(paste0(plot_fol,runIDs[r],"_",period,"_DR_prob.png"),width = 10, height=7)
  
}

# THIS DOESNT WORK YET
plotDRUse_all_underconstruction = function(runID,runDate,
                     inputfolID, outputfolID,
                     scenarios = 1:5, # what scenarios will be graphed
                     overlaplength = 6, endtrim=NULL, #loadTimeseriesData param
                     model_output_fol = outputFolBase, 
                     model_input_fol = inputFol,
                     SHRLOK = SHRLK,
                     base_fol = baseFol) { 
  # model_output_fol is where model output folder : 
  # instance_in_fol is where model input is
  # plot_fol is where plots should go
  # output_fol: paste0(base_fol,output_fol_base,outputID,"/")
  # plot_fol:   paste0(base_fol,output_fol_base,"plots/")
  # instance_in:paste0(base_fol,input_fol,inputfolID,"/")
  
  plot_fol = paste0(model_output_fol,"plots/")
  if(!dir.exists(plot_fol)){dir.create(plot_fol)}
  
  instance_in_fol = paste0(baseFol,inputFol,inputfolID,"/")
  if(!dir.exists(instance_in_fol)){stop("julia input file doesnt exist ", instance_in_fol)}
  output_fol = paste0(model_output_fol,outputfolID,"/")
  
  # load params
  if(!SHRLK){
    inputs_file = paste0(base_fol,"/Julia_UC_Github/Julia_scripts/inputs_ercot.csv")
  }else{
    inputs_file = paste0(base_fol,"/code/inputs_ercot.csv")
  }
  allinputs = read_csv(inputs_file)
  params = allinputs[,c("input_name",runID)]
  params = spread(params, key = input_name, value = runID)
  
  if("overlaplength" %in% names(params)) {overlaplength = params$overlaplength}
  
  endtrim = overlaplength/2
  print(paste("endtrim set to", endtrim))
  
  # load DR production
  drprod = loadTimeseriesData(output_fol,"DR_production",overlaplength,2, probabilities=F,instance_in_fol,params$nrandp,
                              dist_ID = params$stochID, endtrim)
  
  # load and set up demand #
  periodinfo = strsplit(period,"p|_")[[1]] 
  numperiod=as.numeric(periodinfo[2])
  firstperiod = as.numeric(periodinfo[3])
  lastperiod = as.numeric(periodinfo[4])
  dem_base = read_csv(paste0(model_input_fol,"ercot_default/ercot_demand_2016.csv"))
  demchange = read_csv(paste0(instance_in_fol,"demandScenarios_vdem_ARMA26.0_",period,".csv"))
#TODO: read in ALL ARMA scenarios into demchange, add a t column
  # Complication -- these will have overlap! they will not be the same (by scenario) when they overlap, so need to apply endtrim/overlap rules
  # can I use loadTimeseriesData? check format.
  demrealo1 = dem_base$demand[firstperiod:lastperiod] * demchange$V1
  
#TODO: do I really need both demreal and demrealo1? probably not, consolidate.
#TODO: before creating demreal, subselect dem_base for the timesteps included in the demchange data/in the modeled periods
  demreal = dem_base$demand[firstperiod:lastperiod] * demchange
  demreal$t = firstperiod:lastperiod
  demreal = gather(demreal,key = "scenario",value = "demand",-t) 
  demreal$scenarionum = substr(demreal$scenario,2,4)
  
  # select demand from just one period #
  drprodoneperiod = filter(drprod,nperiod == numperiod)
  drprodoneperiod$scenarionum = substr(drprodoneperiod$scenario,2,4)
  demprod = merge(demreal,drprodoneperiod,by=c("t","scenarionum")) 
  
#TODO: adjust plotting to be full timeframe, add vertical lines separating periods
  # plot demand and DR production
  ggplot(filter(demprod,scenarionum %in% scenarios))+ 
    facet_wrap(~scenario.x) + 
    geom_line(aes(x=t-min(t), y=(value*10)+30000), color="blue")+
    geom_line(aes(x=t-min(t),y=demand)) +
    # scale_color_gradient(low="black",high="red")+
    ggtitle(paste(runIDs[r], "Period 10 demand and DR Production")) +
    ggsave(paste0(plot_fol,runIDs[r],"_period10demand_DRproduction.png"),width = 10, height=7)
  
  # plot dr commitment
  drcomtoneperiod = filter(drcommit, nperiod == numperiod)
  drcomtoneperiod$scenarionum = substr(drcomtoneperiod$scenario,2,4)
  demcomt = merge(demreal, drcomtoneperiod, by=c("t","scenarionum"))
  # print(names(demcomt))
  # print(head(demcomt))
  
  ggplot(filter(demcomt,scenarionum %in% scenarios))+ 
    facet_wrap(~scenario.x) + 
    geom_line(aes(x=t-min(t), y=(value*10000)+30000), color="blue")+
    geom_line(aes(x=t-min(t),y=demand)) +
    # scale_color_gradient(low="black",high="red")+
    ggtitle(paste(runIDs[r], paste("Period",numperiod,"demand and DR Commitment"))) +
    ggsave(paste0(plot_fol,runIDs[r],"_period",numperiod,"demand_DRcommitment.png"),width = 10, height=7)
  
  # plot both together
  demprod = rename(demprod, production = value)
  drcomtoneperiod = rename(drcomtoneperiod, commitment = value)
  dralldata = merge(drcomtoneperiod, demprod, by=c("t","scenarionum"))
  # print(names(dralldata))
  ggplot(filter(dralldata,scenarionum %in% scenarios))+ 
    facet_wrap(~scenario.x) + 
    geom_line(aes(x=t-min(t), y=(production*10)+30000), color="blue")+
    geom_point(aes(x=t-min(t), y=(production*10)+30000, color = commitment), shape=1, size = 0.5) + 
    geom_line(aes(x=t-min(t),y=demand)) +
    scale_color_gradient(low="black",high="red")+
    ggtitle(paste(runIDs[r], paste("Period",numperiod,"demand and DR production with commitment in red"))) +
    ggsave(paste0(plot_fol,runIDs[r],"_period",numperiod,"demand_DRfunction.png"),width = 10, height=7)
  
}

fuelBreakdown = function(prodgendat,plotfol,runName,plots=T){
  # takes production data and calculates expected amount
  # of production by each type of generator
  # returns a dataframe with that information
  # optionally saves a bar chart with that information
  # Patricia Levi March 2019
  
  prod_expected = prodgendat %>%
    group_by(GEN_IND,t,Fuel) %>%
    summarise(eProd = sum(prob * MWout))
  
  prod_byfuel = prod_expected %>%
    group_by(Fuel) %>%
    summarise(totEprod = sum(eProd))
  totalprod = sum(prod_byfuel$totEprod)
  
  prod_byfuel$prodFrac = prod_byfuel$totEprod/totalprod
  prod_byfuel$lab = paste0(round(100* prod_byfuel$prodFrac, 1),"%")
  
  if(plots){
  ggplot(prod_byfuel,aes(y=prodFrac,x=Fuel)) + geom_col() +
      ggtitle(paste0("Expected generation breakdown for: ", runName))+
      labs(x="Fuel Type",y="Percentage of total generation") +theme_bw() +
      theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
      scale_y_continuous(labels = scales::percent) +
      geom_text(data=prod_byfuel,aes(x=Fuel,y=prodFrac,label=lab),vjust=0, nudge_y=0.008,size=3) +
      ggsave(paste0(plotfol,runName,"_fuelBreakdown_bar.png"),width=6,height=4)
  }
  return(prod_byfuel)
}

rampInfo = function(prodgendat,runName){
  # calculates the max and min ramp rates by SLOW/FAST/DR and for all dispatchabe gen
  # Also returns the *time/date* (or at least the period number?) of these ramps
  
  # assign speed to be SLOW/FAST/DR
  drsel = which(prodgendat$Fuel == "DR")
  prodgendat$speed[drsel] = "DR"
  
  # assign RE T/F column
  REsel = which(prodgendat$Fuel %in% c("DR","SOLAR","WIND")) # do I want to include Hydro in here? Nah
  prodgendat$REgen = F
  prodgendat$REgen[REsel] = T
  
  # ramp by non-RE
  # find ramp by scenario, RE, timestep
  prodrampRE = prodgendat %>%
    group_by(scenario,REgen,t) %>%
    summarise(MWtot = sum(MWout)) %>%
    group_by(scenario,REgen) %>%
    mutate(ramp = MWtot - lag(MWtot, default=0))%>%
    group_by(REgen) %>%
    summarise(maxramp = max(ramp),
              minramp = min(ramp),
              pct99.9th = quantile(ramp,probs = 0.999,na.rm=T),
              pct99th = quantile(ramp,probs = 0.99,na.rm=T))
  prodrampRE$speed = "all"
  
  # ramp by non-RE and speed
  # find ramp by scenario, RE, timestep
  prodrampREspeed = prodgendat %>%
    group_by(scenario,REgen,speed,t) %>%
    summarise(MWtot = sum(MWout)) %>%
    group_by(scenario,REgen,speed) %>%
    mutate(ramp = MWtot - lag(MWtot, default=0))%>%
    group_by(REgen,speed) %>%
    summarise(maxramp = max(ramp),
              minramp = min(ramp),
              pct99.9th = quantile(ramp,probs = 0.999,na.rm=T),
              pct99th = quantile(ramp,probs = 0.99,na.rm=T))
  
  # consolidate and return
  output = bind_rows(prodrampRE,prodrampREspeed)
  output$runName = runName
  return(output)
}


drDispatchStats_underConstruction = function(runID,runDate,
                           inputfolID, 
                           scenarios = 1:5, # what scenarios will be graphed
                           overlaplength = 6, #loadTimeseriesData param
                           period = "p2_1020_1140", 
                           model_output_fol = outputFolBase, 
                           model_input_fol = inputFol,
                           SHRLOK = SHRLK,
                           base_fol = baseFol, endtrim=NULL){
  # desired outputs:
  #   how many events happen per period
  #   how many events happen total?
  #   what is the distribution of the event length?
  #   what is the distribution of dispatch level (eg 0%-100%)
  
  # how should I deal with scenarios? median or mean? and max? look into some fancy plotting with error bars for max and min?
  
  # check filepaths
  plot_fol = paste0(model_output_fol,"plots/")
  if(!dir.exists(plot_fol)){dir.create(plot_fol)}
  
  instance_in_fol = paste0(model_input_fol,inputfolID,"/")
  if(!dir.exists(instance_in_fol)){stop("julia input file doesnt exist ", instance_in_fol)}
  outputfolID = paste0(runID,"_",runDate)
  output_fol = paste0(model_output_fol,outputfolID,"/")
  # dir.exists(output_fol)
  
  # load params
  inputfilename = list.files(path = output_fol,pattern = "inputfile*")[1]
  inputs = read_csv(paste0(output_fol,inputfilename))
  # trim off useless third column
  print(paste("inputs has ",ncol(inputs),"columns, file name is ", inputfilename))
  inputs = inputs[,1:2]
  params = spread(inputs, key = input_name, value = runID)
  
  if("overlaplength" %in% names(params)) {overlaplength = params$overlaplength
  } else { warning("No overlaplength in inputfile for ",outputfolID, ", using default")}
  
  if(is.null(endtrim)){
    endtrim = overlaplength/2
    print(paste("endtrim set to", endtrim))
  }
  
  # load DR production
  drprod = loadTimeseriesData(output_fol,"DR_production",overlaplength,2, probabilities=F,instance_in_fol,params$nrandp,dist_ID = params$stochID,endtrim)
  
  # load DR commitment
  allcomt = loadTimeseriesData(output_fol,"u_commitment",overlaplength,2, probabilities=F,instance_in_fol,params$nrandp,dist_ID = params$stochID,endtrim)
  drcomt = filter(allcomt,str_detect(GEN_IND,"DR-"))
  rm(allcomt) #memory management
  
  # Create a set of columns identifying event # for each scenario
  # and a second set of columns identifying, for each event, how many hours into the event we are
  hours = sort(unique(drprod$t))
  for(i in 1:length(hours)){
    # probably easier to do this with binary commitment data...
    # we want to count the transition from 0 to nonzero.
    # when that occurs, (t)-(t-1) == (t)
    # could iterate across all scenarios, and within each do step by step analysis
    # after each one, merge in the event column... need to make sure it does not overwrite
    
    # would realllly like to know how I did this for CPUC
    # should I table this till tomorrow?
  }
  
  # identify mean/max/min number of events across scenarios
  
  # identify mean/max/min event length across scenarios
  
}