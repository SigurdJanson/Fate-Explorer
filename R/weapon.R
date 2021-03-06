# Weapon R6
library(R6)
require(jsonlite)
source("./dicelogic.R")
source("./rules.R")
source("./readoptjson.R")


# BASE CLASS =====================================================

##' WeaponBase class (abstract base class for weapons)
##' This class wraps basic functions.
##' @importFrom R6 R6Class
##' @export
WeaponBase <- R6Class(
  "WeaponBase", 
  active = list(
    #' Weapon name (string, property)
    Name = function(value) {
      if (missing(value)) {
        return(private$.Name)
      } else {
        private$.Name <- value
        private$OnValueChange()
      }
    },
    
    #' Weapon type (.WeaponType, property)
    Type = function(value) {
      if (missing(value)) {
        return(private$.Type)
      } else {
        if (value %in% .WeaponType || value %in% names(.WeaponType)) {
          private$.Type <- .WeaponType[value]
          private$OnValueChange()
        } else stop("Unknown weapon type")
      }
    },
    
    #' Combat technique of the weapon (`.ComTecs` Id, property)
    Technique = function(value) {
      if (missing(value)) {
        return(private$.Technique)
      } else {
        private$.Technique <- value
        private$OnValueChange()
      }
    },
    
    #' Range of the weapon (`.CloseCombatRange`, property)
    Range = function(value) {
      if (missing(value)) {
        return(private$.Range)
      } else {
        private$.Range <- value
        private$OnValueChange()
      }
    },
    
    #' Combat skill (property))
    Skill = function(value) {
      if (missing(value)) {
        return(private$.Skill)
      } else {
        private$.Skill <- as.integer(value)
        names(private$.Skill) <- names(.CombatAction)
        private$OnValueChange()
      }
    },
    
    #' Weapon damage, i.e. hit points (`[N]d[DP]+[Bonus]`, property)
    Damage = function(value) {
      if (missing(value)) {
        return(private$.Damage)
      } else {
        private$.Damage <- as.integer(value)
        names(private$.Damage) <- c("N", "DP", "Bonus")
        private$OnValueChange()
      }
    },
    
    #' Permanent weapons modifier (integer, property)
    Modifier = function(value) {
      if (missing(value)) {
        return(private$.Modifier)
      } else {
        private$.Modifier <- as.integer(value)
        private$OnValueChange()
      }
    }
  ),
  public = list(

  LastRoll     = NA, # die roll
  LastAction   = NA, # Parry or Attack
  LastModifier = NA, # additional situation dependent modifier
  LastResult   = NA, # Critical, Success, Fail, Botch
  LastDamage   = NA, # Hit points
  ConfirmationMissing = NA, # T/F - does last roll wait for confirmation? 
  ConfirmRoll  = NA, 
  Confirmed    = NA,
  LastFumbleEffect = NA, # EffectOfFumble: consequence of 2d6
  
  #' Constructor
  #' @param Weapon name of the weapon (character) or a list containing the data
  #' @param Abilities Character abilities (data frame)
  #' @param CombatTecSkills Named list of combat tech skills 
  #' (names are the `combattechID`)
  #' @return `self`
  initialize = function(Weapon = NULL, Abilities = NULL, CombatTecSkills = NULL, ...) {
    if (missing(Weapon)) {
      args <- list(...)
      private$.Name <- NA
      private$.Type <- NA
      private$.Technique <- NA
      private$.Range  <- NA
      self$Skill  <- unlist(args[["Skill"]])
      self$Damage <- unlist(args[["Damage"]])
      private$.Modifier <- 0L
    } else {
      if (is.character(Weapon)) # `Weapon` is a name or ID
        private$RawWeaponData <- GetWeapons(Weapon)
      else 
        private$RawWeaponData <- Weapon
      
      private$.Name      <- private$RawWeaponData[["name"]]
      private$.Type      <- .WeaponType[1+ private$RawWeaponData[["armed"]] + !private$RawWeaponData[["clsrng"]] ]
      private$.Technique <- private$RawWeaponData[["combattechID"]]
      private$.Range     <- private$RawWeaponData[["range"]]
      self$CalcSkill(Abilities, CombatTecSkills)
      self$CalcDamage(Abilities)
      private$.Modifier  <- 0L
    }
    invisible(self)
  },
  
  # CALLBACK SECTION
  RegisterOnValueChange = function(Callback) {
    if (mode(Callback) != "function") 
      stop(sprintf("Cannot register object of type '%s' as callback"), typeof(Callback))
    
    #if (!(Callback %in% private$ValueChangeCallbacks)) # avoid duplicates
    if (!(any(sapply(private$ValueChangeCallbacks, identical, Callback))))
      private$ValueChangeCallbacks <- c(private$ValueChangeCallbacks, Callback)
  },
  UnregisterOnValueChange = function(Callback) {
    if (mode(Callback) != "function")
      stop(sprintf("Cannot register object of type %s as callback"), typeof(Callback))
    
    # Use `setdiff` because duplicates should not exist
    private$ValueChangeCallbacks <- setdiff(private$ValueChangeCallbacks, c(Callback))
  },
  
  
  #' CalcSkill
  #' Computes weapons skill for character
  #' @param CharAbs Data frame of character abilities
  #' @param CombatTecSkill A single value for the combat skill of the weapon's technique
  #' @return `self`
  CalcSkill = function(CharAbs, CombatTecSkill) {
    # if RawWeaponData has not been enriched by character data, yet, do so ...
    if (is.null(private$RawWeaponData[["AT.Skill"]]) || is.null(private$RawWeaponData[["PA.Skill"]])) {
      AtPaSkill <- GetCombatSkill(self$Name, CharAbs, Skill = CombatTecSkill)
      private$RawWeaponData[["AT.Skill"]] <- AtPaSkill$AT
      private$RawWeaponData[["PA.Skill"]] <- AtPaSkill$PA
    }
    ##TODO: DodgeSkill <- GetDodgeSkill()

    self$Skill <- c(Attack = private$RawWeaponData[["AT.Skill"]], 
                    Parry  = private$RawWeaponData[["PA.Skill"]], 
                    Dodge  = ceiling(CharAbs[["ATTR_6"]] / 2L))
    return(invisible(self))
  },

  
  #' CalcDamage
  #' Computes the hit point formula of the weapon. It takes the 
  #' character's abilities into account to get the bonus right.
  #' @details The damage is determined by three components: [N]d[DP] + [Bonus]
  #' @param CharAbs The character's abilities
  #' @return Invisible returns `self`
  CalcDamage = function(CharAbs) {
    # if RawWeaponData has not been enriched by character data, yet, do so ...
    if (is.null(private$RawWeaponData[["damageDiceNumber"]]) || 
        is.null(private$RawWeaponData[["damageDiceSides"]])  ||
        is.null(private$RawWeaponData[["damageFlat"]])) {
      DamageDice <- unlist(strsplit(private$RawWeaponData[["damage"]], split = "W"))
      private$RawWeaponData[["damageDiceNumber"]] <- as.integer(DamageDice[1])
      private$RawWeaponData[["damageDiceSides"]]  <- as.integer(DamageDice[2])
      Bonus <- as.integer(private$RawWeaponData[["bonus"]])
      if (!isTruthy(Bonus)) Bonus <- 0
      private$RawWeaponData[["damageFlat"]] <- Bonus + GetHitpointBonus(self$Name, Abilities = CharAbs)
    }
    
    self$Damage <- c(N = private$RawWeaponData[["damageDiceNumber"]], 
                     DP = private$RawWeaponData[["damageDiceSides"]], 
                     Bonus = private$RawWeaponData[["damageFlat"]])

    return(invisible(self))
  },

  
  Attack = function(Modifier = 0L) self$Roll("Attack", Modifier), # wrapper
  Parry  = function(Modifier = 0L) self$Roll("Parry", Modifier), # wrapper
  Dodge  = function(Modifier = 0L) self$Roll("Dodge", Modifier), # wrapper

  Roll = function(Action = "Attack", Modifier = 0L) {
    # PRECONDITIONS
    if (is.numeric(Action)) {
      if (Action %in% .CombatAction)
        self$LastAction <- Action
      else
        stop("Unknown combat action")
    }
    else {
      if (is.character(Action) && Action %in% names(.CombatAction))
        self$LastAction <- .CombatAction[Action]
      else
        stop("Unknown combat action")
    }
    
    # RUN
    if (length(Modifier) == length(.CombatAction)) # if actions have different modifiers ...
      Modifier <- Modifier[.CombatAction[Action]]  # ... select the right one
    self$LastModifier <- private$.Modifier + Modifier

    Skill <- private$.Skill[[ names(.CombatAction)[self$LastAction] ]]
    
    self$LastRoll <- CombatRoll()
    Verification  <- VerifyCombatRoll(self$LastRoll, Skill, self$LastModifier) # interim variable
    self$LastResult <- .SuccessLevel[Verification]
    
    self$LastDamage <- 0L
    if (self$LastAction == .CombatAction["Attack"])
      if (self$LastResult %in% .SuccessLevel[c("Success", "Critical")])
      {
        self$LastDamage <- DamageRoll(private$.Damage["N"], private$.Damage["DP"], private$.Damage["Bonus"])
      }
    
    self$ConfirmationMissing <- self$LastResult %in% .SuccessLevel[c("Fumble", "Critical")]
    self$ConfirmRoll <- NA
    self$Confirmed   <- NA
    self$LastFumbleEffect <- NA
    
    return(self$LastRoll)
  },
  

  #' Confirm
  #' Confirm the last critical/fumble roll
  #' @return A value from the `.SuccessLevel` enum. `NA` if the last roll was not
  #' a critical or fumble. Also `NA` when the weapon has not been used in this 
  #' session, yet.
  Confirm = function() {
    if (is.na(self$LastRoll)) return(NA)
    if (!self$ConfirmationMissing) return(NA)
      
    self$ConfirmationMissing <- FALSE
    Skill <- private$.Skill[[ names(.CombatAction)[self$LastAction] ]]

    self$ConfirmRoll <- CombatRoll()
    Result <- .SuccessLevel[VerifyCombatRoll(self$ConfirmRoll, Skill, self$LastModifier)]
    # Has previous result been confirmed?
    NewResult <- .SuccessLevel[VerifyConfirmation(names(self$LastResult), names(Result))]
    self$Confirmed <- (NewResult == self$LastResult)
    self$LastResult <- NewResult
    # Effects: Criticals do double damage - Fumble do bad
    if (self$LastResult == .SuccessLevel["Critical"])
      self$LastDamage <- self$LastDamage * 2

    return(Result)
  },
  
  
  #' FumbleRoll
  #' Rolls the consequences of a confirmed fumble roll.
  #' @note This method merely wraps 
  #' @seealso [GetFumbleEffect()] which this function wraps.
  FumbleRoll = function() {
    if (!isTruthy(self$LastFumbleEffect))
      if (self$LastResult == .SuccessLevel["Fumble"]) {
        self$LastFumbleEffect <- GetFumbleEffect(FumbleRoll(),
                                                 names(self$LastAction),
                                                 names(private$.Type))
      }
    return(self$LastFumbleEffect)
  },
  
  
  #' RollNeedsConfirmation
  #' Is a confirmation roll required to complete the fighting roll?
  #' @return `TRUE` if a confirmation roll is required. `FALSE` if
  #' there is no last roll or the last roll is complete.
  RollNeedsConfirmation = function() {
    return(!is.na(self$LastRoll) & self$ConfirmationMissing)
  },
  
  
  #' GetHitPoints
  #' Damage of the last roll
  GetHitPoints = function() {
    return(self$LastDamage)
  },
  
  
  #' CanParry
  #' Does the weapon allow a parry roll?
  CanParry = function() {
    if (!is.na(private$.Technique))
      Can <- IsParryWeapon(CombatTech = private$.Technique) &
             private$.Skill["Parry"] > 0
    else
      Can <- private$.Skill["Parry"] > 0
    return(Can)
  }
), # public

private = list(
  .Name = "",
  .Type = NA,      # .WeaponType # Weaponless, Melee, Ranged, Shield
  .Technique = NA, # .ComTecs # Combat technique
  .Range = NA,     # interpretation differs based on `Type`, either close combat reach or ranged combat range
  .Skill  = c(Attack = 0L, Parry = 0L, Dodge = 0L), # dodge does actually not depend on the active weapon
  .Damage = c(N = 1L, DP = 6L, Bonus = 0L), # [n]d[dp] + [bonus]
  .Modifier = 0L,  # permanent default modifier because of special abilities
  RawWeaponData = NULL,

  # Callbacks to notify other changes in the weapon
  ValueChangeCallbacks = NULL,
  
  OnValueChange = function() {
    if (length(private$ValueChangeCallbacks) > 0)
      for (f in private$ValueChangeCallbacks)
        do.call(f, alist(self))
  }
))


# MELEE =====================================================

##' MeleeWeapon class
##' @importFrom R6 R6Class
##' @export
MeleeWeapon <- R6Class("MeleeWeapon", 
  inherit = WeaponBase, 
  public = list(

    #' Constructor
    #' @param Weapon name of the weapon (character)
    #' @param Abilities Character abilities (data frame)
    #' @param CombatTecSkills Named list of combat tech skills (name is the combattec ID)
    #' @return `self`
    initialize = function(Weapon, Abilities, CombatTecSkills, ...) {
      super$initialize(Weapon, Abilities, CombatTecSkills, ...)
      
      if (!missing(Weapon)) {
        if (!(private$RawWeaponData[["clsrng"]])) # if ranged weapon
          stop("This class is for close combat only")
      }

      invisible(self)
    },
    
    
    #' CalcSkill
    #' Computes weapons skill for character
    #' @param CharAbs Data frame of character abilities
    #' @param CombatTecSkill A single value for the combat skill of the weapon's technique
    #' @return Invisibly returns `self`
    CalcSkill = function(CharAbs, CombatTecSkill) {
      super$CalcSkill(CharAbs, CombatTecSkill)
      return(invisible(self))
    },

    
    #' CalcDamage
    #' Computes the hit point formula of the weapon. It takes the 
    #' character's abilities into account to get the bonus right.
    #' @details The damage is determined by three components: [N]d[DP] + [Bonus]
    #' @param CharAbs The character's abilities
    #' @return Invisibly returns `self` 
    CalcDamage = function(CharAbs) {
      return(invisible(super$CalcDamage(CharAbs)))
    },
    

    #' Roll
    Roll = function(Action = "Attack", Modifier = 0L) {
      return(super$Roll(Action, Modifier))
    }
))



# RANGED =====================================================

##' RangedWeapon class
##' @importFrom R6 R6Class
##' @export
RangedWeapon <- R6Class("RangedWeapon", 
  inherit = WeaponBase, 
  public = list(
  
  #' Constructor
  #' @param Weapon name of the weapon (character)
  #' @param Abilities Character abilities (data frame)
  #' @param CombatTecSkills Named list of combat tech skills (name is the combattec ID)
  #' @return `self`
  initialize = function(Weapon, Abilities, CombatTecSkills, ...) {
   if (is.character(Weapon)) Weapon <- GetWeapons(Weapon, "Ranged")
   super$initialize(Weapon, Abilities, CombatTecSkills, ...)
   
    if (!missing(Weapon)) {
      if (private$RawWeaponData[["clsrng"]]) # if ranged weapon
        stop("This class is for close combat only")
    }
   
   invisible(self)
  },
  
  
  #' CalcSkill
  #' Computes weapons skill for character
  #' @param CharAbs Data frame of character abilities
  #' @param CombatTecSkill A single value for the combat skill of the weapon's technique
  #' @return `self`
  CalcSkill = function(CharAbs, CombatTecSkill) {
   AtPaSkill  <- GetCombatSkill(self$Name, CharAbs, Skill = CombatTecSkill)
   self$Skill <- c(Attack = AtPaSkill$AT, 
                   Parry = 0L, 
                   Dodge = ceiling(CharAbs[["ATTR_6"]] / 2L))
   return(invisible(self))
  },
  
  CalcDamage = function(CharAbs) {
   super$CalcDamage(CharAbs)
   return(invisible(self))
  },
  
  Roll = function(Action = "Attack", Modifier = 0L) {
    # PRECONDITIONS
    if(Action == "Parry" || Action == .CombatAction["Parry"])
      stop("Ranged weapons cannot be used to parry attacks")
    
    super$Roll(Action, Modifier)
    return(self$LastRoll)
  }
))

# ab <- structure(list(ATTR_1 = 12L, ATTR_2 = 11L, ATTR_3 = 13L, ATTR_4 = 14L,
#                      ATTR_5 = 13L, ATTR_6 = 16L, ATTR_7 = 11L, ATTR_8 = 11L),
#                 class = "data.frame", row.names = c(NA, -1L))
# ct <- list(CT_3 = 15, CT_9 = 15, CT_12 = 12, CT_14 = 13)
# #setwd("./R") #for testing purposes
#  W <- WeaponBase$new("Waffenlos", ab, ct) #"Waqqif"
#  print(W$Roll("Attack", .CombatAction))
# #setwd("../") #for testing purposes
