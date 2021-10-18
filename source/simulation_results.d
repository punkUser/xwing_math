public struct TokenResults
{
    public struct Field
    {
        string field;       // Compile-time field name in TokenState. i.e. "attack_tokens.field" should be valid D code
        string name;        // UI name to use for the field
    };    

    public void initialize(const(Field)[] fields, T)(double probability, T state) nothrow
    {
        assert(fields.length <= m_values.length);

        m_fields = fields;
        m_initialized = true;
        m_values[] = 0.0;
        static foreach(i, field; fields)
        {
            mixin("m_values[i] = probability * cast(double)state." ~ field.field ~ ";");
        }
    }

    // Used for computing weighted probabilities of various results
    ref TokenResults opOpAssign(string op)(in TokenResults rhs) nothrow if (op == "+")
    {
        // Super hacky, but good enough for now!
        if (!m_initialized)
        {
            m_fields = rhs.m_fields;
            m_values = rhs.m_values;
            m_initialized = true;
        }
        else
        {
            m_values[] += rhs.m_values[];
        }
        return this;
    }

    // NOTE: Picking a reasonable size that covers max # of token types for now
    private const(Field)[] m_fields;
    private double[16] m_values;
    private bool m_initialized = false;

    // Could do an iteration range or something but this is good enough for now
    public size_t field_count() const nothrow { return m_fields.length; }
    public string field_name(size_t i) const nothrow { return m_fields[i].name; }
    public double result(size_t i) const nothrow { return m_values[i]; }
};


public struct SimulationResult
{
    double probability = 0.0f;
    double hits = 0;
    double crits = 0;
    TokenResults attack_tokens;
    TokenResults defense_tokens;
};

public SimulationResult accumulate_result(SimulationResult a, SimulationResult b) nothrow
{
    a.probability       += b.probability;
    a.hits              += b.hits;
    a.crits             += b.crits;
    a.attack_tokens     += b.attack_tokens;
    a.defense_tokens    += b.defense_tokens;
    return a;
}

// Accumulated results
// TODO: Make into a class with handy utilities
public struct SimulationResults
{
    SimulationResult[] total_hits_pdf;
    SimulationResult total_sum;
    double at_least_one_crit_probability = 0.0;
};
