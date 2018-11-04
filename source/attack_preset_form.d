import attack_form;
import defense_form;
import simulation_state2;
import simulation_setup2;
import form;

import std.bitmanip;

public enum AttackPreset : ubyte
{
    // NOTE: Do not change the order or it will invalidate links!
    _2d = 0,
    _2dHowlrunner,
    _3d,
    _3dHowlrunner,
    _4d,
    _4dProtonTorpedoes,
    _4dProtonTorpedoesWedge,
    Count
};

align(1) struct AttackPresetForm
{
    // TODO: Improve our utility functions to deal with simple fields properly
    mixin(bitfields!(
        ubyte, "preset",     8, // AttackPreset enum
        bool,  "enabled",    1,
        bool,  "focus",      1,
        bool,  "lock",       1,

        uint,  "",           5,
    ));

    static AttackPresetForm defaults(int index = 0)
    {
        AttackPresetForm defaults;
        defaults.enabled = (index == 0);
        return defaults;
    }
}

public string attack_preset_url(ubyte attacker)
{
    switch (attacker)
    {
        case AttackPreset._2d:                      return "IQAAAAAAAAA";
        case AttackPreset._2dHowlrunner:            return "IQAAAAAEAAA";
        case AttackPreset._3d:                      return "MQAAAAAAAAA";
        case AttackPreset._3dHowlrunner:            return "MQAAAAAEAAA";
        case AttackPreset._4d:                      return "QQAAAAAAAAA";
        case AttackPreset._4dProtonTorpedoes:       return "QQAAgAAAAAA";
        case AttackPreset._4dProtonTorpedoesWedge:  return "QQAAgADgAQA";
        default:                                    return "IQAAAAAAAAA";       // Failsafe!
    }
}

public TokenState to_attack_tokens2(ref const(AttackPresetForm) preset_form)
{
    // Avoid ambiguity between the two modules...
    import attack_form : attack_form_tokens = to_attack_tokens2;

    auto attack_form = create_form_from_url!AttackForm(attack_preset_url(preset_form.preset), 0);
    auto tokens = attack_form_tokens(attack_form);

    // Replace any tokens with ones that we control explicitly. In theory these should not be part of the enum anyways
    tokens.focus = preset_form.focus ? 1 : 0;
    tokens.lock  = preset_form.lock  ? 1 : 0;

    return tokens;
}

public SimulationSetup to_simulation_setup2(ref const(AttackPresetForm) attack, ref const(DefenseForm) defense_form)
{
    // Avoid ambiguity between the two modules...
    import simulation_setup2 : attack_form_setup = to_simulation_setup2;

    auto attack_form = create_form_from_url!AttackForm(attack_preset_url(attack.preset), 0);
    return attack_form_setup(attack_form, defense_form);
}
