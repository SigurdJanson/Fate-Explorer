
sidebarLayout(
  sidebarPanel(
    fluidRow(
      column(width=5,
           conditionalPanel(
               condition = "output.ShowSetupWeapons",  #see "tab_setup_srv"
               checkboxInput("chbPredefinedWeapon", i18n$t("Character Weapon"), FALSE)
      )),
      column(width = 7,
           conditionalPanel(
               condition = "output.ShowPredefinedWeapons",
               selectizeInput("cmbCombatSelectWeapon", NULL, choices = "",
                              options = list(
                                placeholder = i18n$t("Select your weapon"),
                                onInitialize = I('function() { this.setValue(""); }'))),
               hr())
    )),
    fluidRow(
      column(6L, p("Grundwert", style = "font-weight: bold;")), column(6L, p("Effektiver Wert", style = "font-weight: bold;"))
    ), fluidRow(
      column(6L, numericInputIcon("inpAttackValue", i18n$t("Attack"), min = 1L, max = 20L, value = 11L, icon = gicon("battle-axe"))),
      column(6L, disabled(numericInputIcon("inpAttackMod", "\u00a0", value = 0L, icon = list("")))),
    ), fluidRow(
      column(6L, numericInputIcon("inpParryValue",  i18n$t("Parry"),  min = 1L, max = 20L, value = 7L, icon = gicon("shield"))),
      column(6L, disabled(numericInputIcon("inpParryMod",  "\u00a0", value = 0L, icon = list("")))),
    ), fluidRow(
      column(6L, numericInputIcon("inpDodgeValue",  i18n$t("Dodge"),  min = 1L, max = 20L, value = 5L, icon = gicon("dodge"))),
      column(6L, disabled(numericInputIcon("inpDodgeMod",  "\u00a0", value = 0L, icon = list("")))),
    ),
    fluidRow( # Modifiers -----
        column(
          width = 8,
          div(style="float:right",
              conditionalPanel(condition = "input.inpCombatMod < 0", 
                               gicon("minus-circle"), i18n$t("Impediment")),
              conditionalPanel(condition = "input.inpCombatMod > 0", 
                               gicon("plus-circle"), i18n$t("Advantage"))
          ),
          sliderInput("inpCombatMod", i18n$t("Modifier"),  min = -10L, max = 10L, step = 1L, value = 0L),
        ), column(width = 4, dlgCombatModsModuleUI("btnCombatMods", i18n))
    ),
    fluidRow(
      column(12L, p(i18n$t("Hit points"), style = "font-weight: bold;")),
      column(6L, numericInputIcon("inpDamageDieCount", i18n$t("Dice 4 Damage"), value = 1L, min = 1L, 
                 width = "100%", icon = list(NULL, "W6"))),
      column(6L, numericInputIcon("inpDamage", i18n$t("Modifier"), value = 2L, min = 0L, 
                 width = "100%", icon = list("+")))
    ),
    hr()
  ),
  mainPanel(
    uiOutput("uiCombatRollButtons"),

    hr(),
    htmlOutput("uiCombatRoll"),
    htmlOutput("uiInitiativeRoll"),
    
    conditionalPanel(
      condition = "output.ShowWeaponDetails",
      hr(),
      htmlOutput("WeaponDetails")
    ),
    conditionalPanel(
      condition = "output.ShowExploreFightingChances",
      h3(i18n$t("Combat Roll")),
      plotOutput("imgAttackChances", width = "100%", height = "200px")
    )
  )
)
