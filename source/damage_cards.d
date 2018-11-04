import std.bitmanip;

// DAMAGE DECK:
// 
// Definitely relevant as they produce additional damage:
// - 5x Direct Hit: Suffer 1 [hit] damage. Then repair this card.
// - 4x Fuel Leak: After you suffer 1 [crit] damage, suffer 1 [hit] damage and repair this card.
// - 2x Hull Breach: Before you would suffer 1 or more [hit] damage, suffer that much [crit] damage instead.
// Also relevant as they affect ship stats:
// - 2x Structural Damage: While you defender, roll 1 fewer defense die.
//
// - 20x "other" cards in the damage deck that we don't consider specifically.
// NOTE: If we look at "exposing" damage cards though we'll have to at least track if they flip immediately or not.
// For now we just consider them generic face-up cards with no additional relevant effects.
//
// Might be relevant in the future for interactions with certain effects:
// - 2x Panicked Pilot: Gain 2 stress tokens. Then repair this card.
//
// As long as we don't model attacker damage cards (self-incflicted or whatever) or actions (token refresh),
// that should be all we need for the moment.

struct DamageCards
{
    mixin(bitfields!(
        ubyte, "direct_hit_count",      3,      // 0..5
        ubyte, "fuel_leak_count",       3,      // 0..4
        ubyte, "hull_breach_count",     2,      // 0..2
        ubyte, "structural_count",      2,      // 0..2
        ubyte, "other_crit_count",      5,      // 0..20
        ubyte, "",                      1,
    ));
};