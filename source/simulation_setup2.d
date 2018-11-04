import attack_form;
import defense_form;
import form;

// Class for reference semantics since we now pass this around a lot
public class SimulationSetup
{
    public struct Attack
    {
        int dice = 0;

        bool roll_all_hits = false;     // Force initial roll to be all hits
        
        // Add
        int add_blank_count = 0;
        int add_focus_count = 0;

        int reroll_1_count = 0;
        int reroll_2_count = 0;         // reroll up to 2 dice
        int reroll_3_count = 0;         // reroll up to 3 dice

        // Change
        int focus_to_hit_count = 0;
        int focus_to_crit_count = 0;
        int any_to_hit_count = 0;
        int hit_to_crit_count = 0;        

        int defense_dice_diff = 0;

        bool heroic = false;
        bool fire_control_system = false;
        bool advanced_targeting_computer = false;
        bool juke = false;        
        bool heavy_laser_cannon = false;
        bool ion_weapon = false;

        bool scum_lando_crew = false;

        bool leebo_pilot = false;
        bool shara_bey_pilot = false;
        bool major_vermeil_pilot = false;
        bool ezra_pilot = false;
        bool scum_lando_pilot = false;
    };
    public Attack attack;

    public struct Defense
    {
        int dice = 0;

        // Add
        int add_blank_count = 0;
        int add_focus_count = 0;
        int add_evade_count = 0;

        int reroll_1_count = 0;
        int reroll_2_count = 0;         // reroll up to 2 dice
        int reroll_3_count = 0;         // reroll up to 3 dice

        // Change
        int focus_to_evade_count = 0;
        int any_to_evade_count = 0;

        bool c3p0 = false;              // Guess 1 unconditionally if calculate available
        bool selfless = false;
        bool biggs = false;
        bool scum_lando_crew = false;
        bool rebel_millennium_falcon = false;    // 1 reroll if evading
        bool heroic = false;

        bool zeb_pilot = false;
        bool leebo_pilot = false;
        bool luke_pilot = false;
        bool shara_bey_pilot = false;
        bool captain_feroph_pilot = false;
        bool laetin_pilot = false;
        bool ezra_pilot = false;
        bool scum_lando_pilot = false;
    };
    public Defense defense;
};


// TODO: This should maybe move somewhere else at this point
public SimulationSetup to_simulation_setup2(ref const(AttackForm) attack, ref const(DefenseForm) defense)
{
    SimulationSetup setup = new SimulationSetup;

    // Grab the relevant form values for this attacker
    setup.attack.dice                         = attack.dice;
    setup.attack.defense_dice_diff            = attack.defense_dice_diff;
    setup.attack.roll_all_hits                = attack.roll_all_hits;

    setup.attack.add_blank_count             += attack.finn_gunner ? 1 : 0;
    setup.attack.reroll_1_count              += attack.howlrunner ? 1 : 0;
    setup.attack.reroll_1_count              += attack.predator ? 1 : 0;
    setup.attack.reroll_1_count              += attack.saw_gerrera_pilot ? 1 : 0;
    setup.attack.reroll_1_count              += attack.pilot == AttackPilot2.Reroll_1 ? 1 : 0;
    setup.attack.reroll_2_count              += attack.pilot == AttackPilot2.Reroll_2 ? 1 : 0;
    setup.attack.reroll_3_count              += attack.pilot == AttackPilot2.Reroll_3 ? 1 : 0;

    setup.attack.focus_to_hit_count          += attack.agent_kallus ? 1 : 0;
    setup.attack.focus_to_crit_count         += attack.pilot == AttackPilot2.RearAdmiralChiraneau ? 1 : 0;
    setup.attack.hit_to_crit_count           += attack.proton_torpedoes;
    setup.attack.hit_to_crit_count           += attack.marksmanship;
    setup.attack.hit_to_crit_count           += attack.pilot == AttackPilot2.GavinDarklighter ? 1 : 0;
    setup.attack.focus_to_hit_count          += attack.fanatical ? 1 : 0;
    setup.attack.any_to_hit_count            += attack.fearless ? 1 : 0;

    setup.attack.leebo_pilot                  = attack.pilot == AttackPilot2.Leebo;
    setup.attack.shara_bey_pilot              = attack.pilot == AttackPilot2.SharaBey;
    setup.attack.major_vermeil_pilot          = attack.pilot == AttackPilot2.MajorVermeil;
    setup.attack.ezra_pilot                   = attack.pilot == AttackPilot2.EzraBridger;
    setup.attack.scum_lando_pilot             = attack.pilot == AttackPilot2.LandoCalrissianScum;

    setup.attack.fire_control_system          = attack.fire_control_system;
    setup.attack.heroic                       = attack.heroic;
    setup.attack.juke                         = attack.juke;
    setup.attack.heavy_laser_cannon           = attack.heavy_laser_cannon;
    setup.attack.ion_weapon                   = attack.ion_weapon;
    setup.attack.advanced_targeting_computer  = attack.ship == AttackShip2.AdvancedTargetingComputer;
    setup.attack.scum_lando_crew              = attack.scum_lando_crew;

    // ****************************************************************************************************************

    setup.defense.dice                         = defense.dice;

    setup.defense.add_blank_count             += defense.finn_gunner ? 1 : 0;
    setup.defense.add_focus_count             += defense.pilot == DefensePilot2.SabineWrenLancer ? 1 : 0;
    setup.defense.add_evade_count             += defense.pilot == DefensePilot2.NorraWexley ? 1 : 0;    

    setup.defense.reroll_1_count              += defense.pilot == DefensePilot2.Reroll_1 ? 1 : 0;
    setup.defense.reroll_1_count              += defense.serissu;
    setup.defense.reroll_2_count              += defense.pilot == DefensePilot2.Reroll_2 ? 1 : 0;
    setup.defense.reroll_3_count              += defense.pilot == DefensePilot2.Reroll_3 ? 1 : 0;

    setup.defense.any_to_evade_count          += defense.ship  == DefenseShip2.ConcordiaFaceoff ? 1 : 0;

    setup.defense.leebo_pilot                  = defense.pilot == DefensePilot2.Leebo;    
    setup.defense.luke_pilot                   = defense.pilot == DefensePilot2.LukeSkywalker;
    setup.defense.shara_bey_pilot              = defense.pilot == DefensePilot2.SharaBey;
    setup.defense.zeb_pilot                    = defense.pilot == DefensePilot2.ZebOrrelios;
    setup.defense.captain_feroph_pilot         = defense.pilot == DefensePilot2.CaptainFeroph;
    setup.defense.laetin_pilot                 = defense.pilot == DefensePilot2.LaetinAshera;
    setup.defense.ezra_pilot                   = defense.pilot == DefensePilot2.EzraBridger;
    setup.defense.scum_lando_pilot             = defense.pilot == DefensePilot2.LandoCalrissianScum;

    setup.defense.c3p0                         = defense.c3p0;
    setup.defense.biggs                        = defense.biggs;
    setup.defense.selfless                     = defense.selfless;
    setup.defense.scum_lando_crew              = defense.scum_lando_crew;
    setup.defense.rebel_millennium_falcon      = defense.rebel_millennium_falcon;
    setup.defense.heroic                       = defense.heroic;

    return setup;
}

// Version that only takes the attack portion
// NOTE: For now we simply create a default/empty defense portion and assume there are no
// defender modifies attack parts, otherwise they would really need to specify both forms in
// the first place.
public SimulationSetup to_simulation_setup2(ref const(AttackForm) attack)
{
    // NOTE: Intentionally *not* DefenseForm.defaults(). See above notes.
    DefenseForm defense = DefenseForm.init;
    return to_simulation_setup2(attack, defense);
}

public SimulationSetup to_simulation_setup2(ref const(DefenseForm) defense)
{
    // NOTE: Intentionally *not* AttackForm.defaults(). See above notes.
    AttackForm attack = AttackForm.init;
    return to_simulation_setup2(attack, defense);
}