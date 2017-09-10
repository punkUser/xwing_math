import simulation;
import dice;

import std.bitmanip;

struct AdvancedForm
{
    // NOTE: DO NOT CHANGE SIZE/ORDER of these fields
    // The entire point in this structure is for consistent serialization
    // Deprecated fields can just be removed from the UI and then unused
    // New fields can be given sensible default values

    // Boolean fields
    mixin(bitfields!(
        bool, "attack_heavy_laser_cannon",    1,
        bool, "attack_fire_control_system",   1,
        bool, "attack_one_damage_on_hit",     1,
        bool, "amad_accuracy_corrector",      1,

        bool, "amad_once_any_to_hit",         1,
        bool, "amad_once_any_to_crit",        1,
        bool, "attack_must_spend_focus",      1,
        bool, "defense_must_spend_focus",     1,

        uint, "",							  8,	// Padding/reserved space
        ));

    // Integer fields
    mixin(bitfields!(
        ubyte, "attack_type",                 4,        // enum MultiAttackType
        ubyte, "attack_dice",                 4,
        ubyte, "attack_focus_token_count",    4,
        ubyte, "attack_target_lock_count",    4,

        ubyte, "amad_add_hit_count",          4,
        ubyte, "amad_add_crit_count",         4,
        ubyte, "amad_add_blank_count",        4,
        ubyte, "amad_add_focus_count",        4,

        ubyte, "amad_reroll_blank_count",     4,
        ubyte, "amad_reroll_focus_count",     4,
        ubyte, "amad_reroll_any_count",		  4,
        ubyte, "amad_focus_to_crit_count",    4,

        ubyte, "amad_focus_to_hit_count",     4,
        ubyte, "amad_blank_to_crit_count",    4,
        ubyte, "amad_blank_to_hit_count",     4,
        ubyte, "amad_blank_to_focus_count",   4,
    ));

    mixin(bitfields!(
        ubyte, "amad_hit_to_crit_count", 	  4,
        ubyte, "amdd_evade_to_focus_count",   4,
        ubyte, "defense_dice", 			      4,
        ubyte, "defense_focus_token_count",   4,

        ubyte, "defense_evade_token_count",   4,
        ubyte, "dmdd_add_blank_count", 	      4,
        ubyte, "dmdd_add_focus_count", 	      4,
        ubyte, "dmdd_add_evade_count", 		  4,

        ubyte, "dmdd_reroll_blank_count", 	  4,
        ubyte, "dmdd_reroll_focus_count", 	  4,
        ubyte, "dmdd_reroll_any_count", 	  4,
        ubyte, "dmdd_blank_to_evade_count",   4,

        ubyte, "dmdd_focus_to_evade_count",   4,
        ubyte, "dmad_hit_to_focus_no_reroll_count", 	  4,

        uint, "",							  8,	// Padding/reserved space
    ));

    // Can always add more on the end, so no need to reserve space explicitly

    static AdvancedForm defaults()
    {
        AdvancedForm defaults;

        // Anything not referenced defaults to 0/false
        defaults.attack_type = MultiAttackType.Single;
        defaults.attack_dice = 3;
        defaults.defense_dice = 3;

        return defaults;
    }
};

//pragma(msg, "sizeof(AdvancedForm) = " ~ to!string(AdvancedForm.sizeof));

SimulationSetup to_simulation_setup(ref const(AdvancedForm) form)
{
    SimulationSetup setup;

    setup.type                       = cast(MultiAttackType)form.attack_type;

    setup.attack_dice                = form.attack_dice;
    setup.attack_tokens.focus        = form.attack_focus_token_count;
    setup.attack_tokens.target_lock  = form.attack_target_lock_count;

    // Once per turn abilities are treated like "tokens" for simulation purposes
    setup.attack_tokens.amad_any_to_hit  = form.amad_once_any_to_hit;
    setup.attack_tokens.amad_any_to_crit = form.amad_once_any_to_crit;
    
    setup.attack_fire_control_system = form.attack_fire_control_system;
    setup.attack_heavy_laser_cannon  = form.attack_heavy_laser_cannon;
    setup.attack_must_spend_focus    = form.attack_must_spend_focus;
    setup.attack_one_damage_on_hit   = form.attack_one_damage_on_hit;

    setup.AMAD.add_hit_count         = form.amad_add_hit_count;
    setup.AMAD.add_crit_count        = form.amad_add_crit_count;
    setup.AMAD.add_blank_count       = form.amad_add_blank_count;
    setup.AMAD.add_focus_count       = form.amad_add_focus_count;
    setup.AMAD.reroll_blank_count    = form.amad_reroll_blank_count;
    setup.AMAD.reroll_focus_count    = form.amad_reroll_focus_count;
    setup.AMAD.reroll_any_count      = form.amad_reroll_any_count;
    setup.AMAD.focus_to_crit_count   = form.amad_focus_to_crit_count;
    setup.AMAD.focus_to_hit_count    = form.amad_focus_to_hit_count;
    setup.AMAD.blank_to_crit_count   = form.amad_blank_to_crit_count;
    setup.AMAD.blank_to_hit_count    = form.amad_blank_to_hit_count;
    setup.AMAD.blank_to_focus_count  = form.amad_blank_to_focus_count;
    setup.AMAD.hit_to_crit_count     = form.amad_hit_to_crit_count;
    setup.AMAD.accuracy_corrector    = form.amad_accuracy_corrector;
    setup.AMDD.evade_to_focus_count  = form.amdd_evade_to_focus_count;

    setup.defense_dice               = form.defense_dice;
    setup.defense_tokens.focus       = form.defense_focus_token_count;
    setup.defense_tokens.evade       = form.defense_evade_token_count;

    setup.defense_must_spend_focus   = form.defense_must_spend_focus;

    setup.DMDD.add_blank_count       = form.dmdd_add_blank_count;
    setup.DMDD.add_focus_count       = form.dmdd_add_focus_count;
    setup.DMDD.add_evade_count       = form.dmdd_add_evade_count;
    setup.DMDD.reroll_blank_count    = form.dmdd_reroll_blank_count;
    setup.DMDD.reroll_focus_count    = form.dmdd_reroll_focus_count;
    setup.DMDD.reroll_any_count      = form.dmdd_reroll_any_count;
    setup.DMDD.blank_to_evade_count  = form.dmdd_blank_to_evade_count;
    setup.DMDD.focus_to_evade_count  = form.dmdd_focus_to_evade_count;
    setup.DMAD.hit_to_focus_no_reroll_count = form.dmad_hit_to_focus_no_reroll_count;

    return setup;
}

