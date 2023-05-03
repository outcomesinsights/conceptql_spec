# ConceptQL Specification

[ConceptQL](https://github.com/outcomesinsights/conceptql) (pronounced concept-Q-L) is a high-level language that allows researchers to unambiguously define their research algorithms.  Over the last 7 years, it has been running in production as the heart of our study-building software, [Jigsaw](https://jigsaw.io)

In that time its implementation has evolved considerably, but it has remained consistent with its original goals.

## Motivation for ConceptQL

Outcomes Insights has built a vast library of research algorithms and applied those algorithms to large databases of claims data.  Early into building the library, we realized we had to overcome two major issues:

1. Methods sections of research papers commonly use natural language to specify the criteria used to build cohorts from a claims database.
    - Algorithms defined in natural language are often imprecise, open to multiple interpretations, and generally difficult to reproduce.
    - Researchers could benefit from a language that removes the ambiguity of natural language while increasing the reproducibility of their research algorithms.
1. Querying against claims databases is often difficult.
    - Hand-coding algorithms to extract cohorts from datasets is time-consuming, error-prone, and opaque.
    - Researchers could benefit from a language that allows algorithms to be defined at a high-level and then gets translated into the appropriate queries against a database.

We developed ConceptQL to address these two issues.

We have written a tool that can read research algorithms defined in ConceptQL.  The tool can create a diagram for the algorithm which makes it easy to visualize and understand.  The tool can also translate the algorithm into a SQL query which runs against data structured in the [Generalized Data Model (GDM)](https://github.com/outcomesinsights/generalized_data_model).  The purpose of the GDM is to standardize the format and content of observational data, so standardized applications, tools and methods can be applied to them.

For instance, using ConceptQL we can take a statement that looks like this:

```JSON
[ "icd9", "412" ]
```

And generate a diagram that looks like this:

```ConceptQL
[
  "icd9",
  "412"
]
```

And generate SQL that looks like this:

```SQL
SELECT *
FROM gdm_data.clinical_codes AS cc
WHERE cc.clinical_code_concept_id IN (
  SELECT id
  FROM concepts
  WHERE vocabulary_id = 'ICD9CM'
    AND concept_code = '412'
)
```

As stated above, one of the goals of ConceptQL is to make it easy to assemble fairly complex queries without having to roll up our sleeves and write raw SQL.  To accommodate this complexity, ConceptQL itself has some complexities of its own.  That said, we believe ConceptQL will help researchers define, hone, and share their research algorithms.

## ConceptQL Overview

### What ConceptQL Looks Like

Perhaps seeing an example will be the quickest way to get a sense of a language.  Here is a trivial example to whet your appetite.  The example is in YAML, but could just as easily be in JSON or any other markup language capable of representing nested sets of heterogeneous arrays and hashes.  In fact, the ConceptQL "language" is a just set of nested arrays and hashes.  If you squint, it might even look a bit like [Lisp](https://en.wikipedia.org/wiki/Lisp_(programming_language)).  Indeed, the nested arrays are [S-expressions](https://en.wikipedia.org/wiki/S-expression).  

ConceptQL is a domain-specific, declarative "language" that represents search criteria with some set operations and temporal operations to glue those criteria together.

```YAML
# Example 1: A simple example in YAML
# This is just a simple array with the first element being 'icd9cm' and the second being '412'
# This example will search the clinical_codes table for all conditions that match the ICD-9 diagnosis code 412.
---
- icd9cm
- 412
```

### ConceptQL Diagrams

Reading ConceptQL in YAML or JSON can be difficult.  It is often easier to explore ConceptQL using directed graphs.  For instance, the diagram for the simple example listed in YAML above is:

```ConceptQL
# All Conditions Matching MI
[
  "icd9",
  "412"
]
```

Each oval depicts an "operator", or rather, a ConceptQL expression.  An arrow between a pair of operators indicates that the records from the operator on the tail of the arrow pass on to the operator at the head of the arrow.  A simple example should help here:

```ConceptQL
# First Office Visit Per Patient
[
  "first",
  [
    "cpt",
    "99214"
  ]
]
```

The diagram above reads "get all procedures that match the CPT 99214 (Office Visit) and then filter them down to the first occurrence (by date) for each person".  More succinctly, "get the first office visit for each patient".  The diagram is much more terse than that and to accurately read the diagram, you need a lot of implicit knowledge about how each operator operates.  Fortunately, this document will impart that knowledge to you.

Please note that all of the diagrams end with an arrow pointing at nothing.  We'll explain why soon.

### Think of Records as a Stream

ConceptQL diagrams have the "leaf" operators at the top and "trunk" operators at the bottom.  You can think of the records of a ConceptQL statement as a flowing stream of data.  The leaf operators, or operators that gather records out of the database, act like tributaries.  The records flow downwards and either join with other records, or filter out other records until the streams emerge at the bottom of the diagram.  Think of each arrow as a stream of records, flowing down through one operator to the next.

The trailing arrow in the diagrams serves as a reminder that every ConceptQL statement yields a stream of records.

### Streams Have Types

You might have noticed that the operators and edges in the diagrams often have a color.  That color represents what "type" of stream the operator or edge represents.  There are several types in ConceptQL, and you'll notice they are somewhat correlated with the tables found in [OMOP's CDM v4.0](https://github.com/OHDSI/CommonDataModel/releases/tag/v4):

- condition_occurrence
    - red
- death
    - brown
- drug_exposure
    - purple
- person
    - blue
- procedure_occurrence
    - green

Each stream has a vocabulary of origin (essentially, the vocabulary used to pull records from the GDM database).  Based on that origin, each stream will have a particular type.  The stream carries this type information as it moves through each operator.  When certain operators, particularly set and temporal operators, need to perform filtering, they can use this type information to determine how to best filter a stream.  There will be much more discussion about types woven throughout this document.  For now, it is sufficient to know that each stream has a type.

You'll also notice that the trailing arrow(s) at the end of the diagrams indicate which types of streams are ultimately passed on at the end of a ConceptQL statement.

### Why Types?

At its inception, ConceptQL was developed to query [OMOP's CDM v4.0](https://github.com/OHDSI/CommonDataModel/releases/tag/v4) and its associated tables.  Each table represented a certain "type" of data (e.g. condition_occurrence, procedure_occurrence, visit_occurrence, etc) and ConceptQL was designed to treat each type of data as distinct from the other types.

Now that ConceptQL runs against the [GDM](https://github.com/outcomesinsights/generalized_data_model), types are far less important, but are still maintained to help users distinguish between the kinds of data a ConceptQL statement is querying.

### What *are* Streams Really?

Though thinking in "streams" is helpful, on a few occasions we need to know what's going on under the hood.

Every table in the GDM structure has a surrogate key column (an ID column).  When we execute a ConceptQL statement, the "streams" that are generated by the statement are just sets of these IDs for rows that matched the ConceptQL criteria.  So each stream is just a set of IDs that point back to some rows in one of the GDM tables.  When a stream has a "type" it is really just that the stream contains records associated with its vocabulary of origin.

So when we execute this ConceptQL statement, the resulting "stream" is all IDs from the `patients` table where the patient is male:

```ConceptQL
# All Male Patients
[
  "gender",
  "Male"
]
```

When we execute this ConceptQL statement, the resulting "stream" is all `clinical_codes` IDs that match ICD-9CM 250.01:

```ConceptQL
# All Condition Occurrences that match ICD-9CM 250.01
[
  "icd9",
  "250.01"
]
```

Generally, it is helpful to just think of those queries generating a "stream of people" or a "stream of conditions" and not worry about the table of origin or the fact that they are just IDs.

When a ConceptQL statement is executed, it yields a final set of streams that are just all the IDs that passed through all the criteria.  What is done with that set of IDs is up to the user who assembled the ConceptQL statement.  If a user gathers all 250.01 Conditions, they will end up with a set of `clinical_codes` IDs.  They could take those IDs and do all sorts of things like:

- Gather the first and last date of occurrence per person
- Count the number of occurrences per person
- Count number of persons with the condition
- Count the total number of occurrences for the entire population

This kind of aggregation and analysis is beyond the scope of ConceptQL.  ConceptQL will get you the IDs of the rows you're interested in, it's up to other parts of the calling system to determine what you do with them.

## Selection Operators

Selection operators are the parts of a ConceptQL statement that search for specific values within the CDM data, e.g. searching the condition_occurrence table for a diagnosis of an old myocardial infarction (ICD-9CM 412) is a selection.  Selection operators are always leaf operators, meaning no operators "feed" into a selection operator.

There are _many_ selection operators.  A list of currently implemented operators is available in Appendix A.

## All Other Operators i.e. Mutation Operators

Virtually all other operators add, remove, filter, or otherwise alter streams of records.  They are discussed in this section.

## Set Operators

Because streams represent sets of records, it makes sense to include operators that operate on sets

### `Union` Operator

- Takes any number of upstream operators and aggregates their streams
    - Unions together streams with identical types
        - Think of streams with the same type flowing together into a single stream
        - We're really just gathering the union of all IDs for identically-typed streams
    - Streams with the different types flow along together concurrently without interacting
        - It does not make sense to union, say, condition_occurrences with procedure_occurrences, so streams with different types won't mingle together, but will continue to flow downstream in parallel

```ConceptQL
# Two streams of the same type (condition_occurrence) joined into a single stream
[
  "union",
  [
    "icd9",
    "412"
  ],
  [
    "icd9",
    "250.01"
  ]
]
```

```ConceptQL
# Two streams of the same type (condition_occurrence) joined into a single stream, then a different stream (procedure_occurrence) flows concurrently
[
  "union",
  [
    "union",
    [
      "icd9",
      "412"
    ],
    [
      "icd9",
      "250.01"
    ]
  ],
  [
    "cpt",
    "99214"
  ]
]
```

```ConceptQL
# Two streams of the same type (condition_occurrence) joined into a single stream, along with a different stream (procedure_occurrence) flows concurrently (same as above example)
[
  "union",
  [
    "icd9",
    "412"
  ],
  [
    "icd9",
    "250.01"
  ],
  [
    "cpt",
    "99214"
  ]
]
```

### `Intersect` Operator

1. Group incoming streams by type
1. For each group of same-type streams
     a. Intersect all streams, yielding a single stream that contains only those IDs common to those streams
1. A single stream for each incoming type is sent downstream
     a. If only a single stream of a type is upstream, that stream is essentially unaltered as it is passed downstream

```ConceptQL
# Yields a single stream of all patients that are male and white.  This involves two person streams and so records are intersected
[
  "intersect",
  [
    "gender",
    "male"
  ],
  [
    "race",
    "white"
  ]
]
```

```ConceptQL
# Yields two streams: a stream of all MI Conditions and a stream of all Male patients.  This is essentially the same behavior as Union in this case
[
  "intersect",
  [
    "icd9",
    "412"
  ],
  [
    "gender",
    "Male"
  ]
]
```

```ConceptQL
# Yields two streams: a stream of all Conditions where MI was Primary Diagnosis and a stream of all White, Male patients.
[
  "intersect",
  [
    "icd9",
    "412"
  ],
  [
    "gender",
    "Male"
  ],
  [
    "race",
    "White"
  ]
]
```

### `Except` Operator

This operator takes two sets of incoming streams, a left-hand stream and a right-hand stream.  The operator matches like-type streams between the left-hand and right-hand streams. The operator removes any records in the left-hand stream if they appear in the right-hand stream.  The operator passes only records for the left-hand stream downstream.  The operator discards all records in the right-hand stream. For example:

```ConceptQL
# All males who are not white
[
  "except",
  {
    "left": [
      "gender",
      "male"
    ],
    "right": [
      "race",
      "white"
    ]
  }
]
```

If the left-hand stream has no types that match the right-hand stream, the left-hand stream passes through unaffected:

```ConceptQL
# All Conditions that are MI
[
  "except",
  {
    "left": [
      "icd9",
      "412"
    ],
    "right": [
      "cpt",
      "99214"
    ]
  }
]
```

And just to show how multiple streams behave:

```ConceptQL
# Passes two streams downstream: a stream of Conditions that are MI (this stream is completely unaffected by the right hand stream) and a stream of People that are Male but not White
[
  "except",
  {
    "left": [
      "union",
      [
        "icd9",
        "412"
      ],
      [
        "gender",
        "Male"
      ]
    ],
    "right": [
      "race",
      "White"
    ]
  }
]
```

### Discussion About Set Operators

#### Q. Why should we allow two different types of streams to continue downstream concurrently?

- This feature lets us do interesting things, like find the first occurrence of either an MI or Death as in the example below
    - Throw in a few more criteria and you could find the first occurrence of all censoring events for each patient

```ConceptQL
# First occurrence of either MI or Death for each patient
[
  "first",
  [
    "union",
    [
      "icd9",
      "412"
    ],
    [
      "death"
    ]
  ]
]
```

#### Q. Why aren't all streams passed forward unaltered?  Why union like-typed streams?

- The way `Intersect` works, if we passed like-typed streams forward without unioning them, Intersect would end up intersecting the two un-unioned like-type streams and that's not what we intended
- Essentially, these two diagrams would be identical:

```ConceptQL
# Two streams: a stream of all Conditions matching either 412 or 250.01 and a stream of Procedures matching 99214
[
  "intersect",
  [
    "union",
    [
      "icd9",
      "412"
    ],
    [
      "icd9",
      "250.01"
    ]
  ],
  [
    "cpt",
    "99214"
  ]
]
```

```ConceptQL
# Two streams: a stream of all Conditions matching either 412 AND 250.01 (an empty stream, a condition cannot be both 412 and 250.01 at the same time) and a stream of Procedures matching 99214
[
  "intersect",
  [
    "intersect",
    [
      "icd9",
      "412"
    ],
    [
      "icd9",
      "250.01"
    ]
  ],
  [
    "cpt",
    "99214"
  ]
]
```

## Time-oriented Operators

All records in a stream carry a start_date and end_date with them.  All temporal comparisons of streams use these two date columns.  Each record in a stream derives its start and end date from its corresponding row in its table of origin.

If a record comes from a table that only has a single date value, the record derives both its start_date and end_date from that single date, e.g. a death record derives both its start_date and end_date from its corresponding row's observation_date.

The person stream is a special case.  Person records use the person's date of birth as the start_date and end_date.  This may sound strange, but we will explain below why this can be useful.

### Relative Temporal Operators

When looking at a set of records for a person, perhaps we want to select just the chronologically first or last record.  Or maybe we want to select the 2nd record or 2nd to last record.  Relative temporal operators provide this type of filtering.  Relative temporal operators use a record's start_date to determine chronological order.

#### `Nth Occurrence` Operator

- Takes a two arguments: the stream to select from and an integer argument
- For the integer argument
    - Positive numbers mean 1st, 2nd, 3rd occurrence in chronological order
        - e.g. 1 => first
        - e.g. 4 => fourth
    - Negative numbers mean 1st, 2nd, 3rd occurrence in reverse chronological order
        - e.g. -1 => last
        - e.g. -4 => fourth from last
    - 0 is undefined?
- Has an optional parameter: `unique`
    - Setting the `unique` parameter to `true` will de-duplicate all upstream records by `patient_id`, `domain`, and `source_code`, creating a set of unique codes per patient.  Then it will find the Nth occurrence from that set of unique codes.

```ConceptQL
# For each patient, select the Condition that represents the second occurrence of an MI
[
  "occurrence",
  2,
  [
    "icd9",
    "412"
  ]
]
```

In the example shown below, the `unique` parameter under the `Nth Occurrence` operator in the algorithm will de-duplicate all upstream records and create a new set of records limited to the first `410.00`, the first `410.01`, the first `250.00`, and the first `250.01` ICD-9 codes for a patient.  The `occurrence` parameter will find the nth of those unique codes.  In the example below, the algorithm will find the second of three unique codes for each patient.  This algorithm ensures that this patient has at least two of the ICD-9 codes listed in the ICD-9 operator.  As a reminder, the `First`, `Last`, and `Nth Occurrence` operators return only one record per patient.  If there are multiple records with the same date that meet the requirements of the `First`, `Last`, and `Nth Occurrence`, an arbitrary row is returned.

```ConceptQL
["occurrence", 2, ["icd9", "410.00", "410.01", "250.00", "250.01"], {"unique": true}]
```

#### `First` Operator

- [Nth Occurrence Operator](#nth-occurrence-operator) that is shorthand for writing ``[ "occurrence", 1 ]``

```ConceptQL
# For each patient, select the Condition that represents the first occurrence of an MI
[
  "first",
  [
    "icd9",
    "412"
  ]
]
```

#### `Last` Operator

- [Nth Occurrence Operator](#nth-occurrence-operator) that is shorthand for writing ``[ "occurrence", -1 ]``

```ConceptQL
# For each patient, select the Condition that represents the last occurrence of an MI
[
  "last",
  [
    "icd9",
    "412"
  ]
]
```

### Date Literals

For situations where we need to represent pre-defined date ranges, we can use "date literal" operators.

#### `Date Range` Operator

- Takes a hash with two elements: { start: \<date-format\>, end: \<date-format\> }
- Creates an inclusive, continuous range of dates defined by a start and end date

#### day

- Takes a single argument: \<date-format\>
- Represents a single day
- Shorthand for creating a date range that starts and ends on the same date
- *Not yet implemented*

#### What is <date-format\>?

Dates follow these formats:

- "YYYY-MM-DD"
    - Four-digit year, two-digit month with leading 0s, two-digit day with leading 0s
- "START"
    - Represents the first date of information available from the data source
- "END"
    - Represents the last date of information available from the data source.

### Temporal Comparison Operators

As described above, each record carries a start and end date, defining its own date range.  It is through these date ranges that we are able to do temporal filtering of streams via temporal operators.

Temporal operators work by comparing a left-hand stream (L) against a right-hand stream (R).  R can be either a set of streams or a pre-defined date range.  Each temporal operator has a comparison operator which defines how it compares dates between L and R.  A temporal operator passes records only from L downstream.  A temporal operator discards all records in the R stream after it makes all comparisons.

```ConceptQL
# All MIs for the year 2010
[
  "during",
  {
    "left": [
      "icd9",
      "412"
    ],
    "right": [
      "date_range",
      {
        "start": "2010-01-01",
        "end": "2010-12-31"
      }
    ]
  }
]
```

When comparing records in L against a set of records in R, the temporal operator compares records in stream L against records in stream R on a person-by-person basis.

- If a person has records in L or R stream, but not in both, none of their records continue downstream
- On a per person basis, the temporal operator joins all records in the L stream to all records in the R stream
    - Any records in the L stream that meet the temporal comparison against any records in the R stream continue downstream

```ConceptQL
# All MIs While Patients had Part A Medicare
[
  "during",
  {
    "left": [
      "icd9",
      "412"
    ],
    "right": [
      "payer",
      "Part A"
    ]
  }
]
```

#### `Any Overlap` Operator

As a foray into defining less strict relationships, we've created the `Any Overlap` operator, which passes through any records in L that overlap whatsoever with a record in R.  This diagram attempts to demonstrate all L records that would qualify as having "any_overlap" with an R record.

![](additional_images/any_overlap.png)

#### Edge Behaviors of Before and After

For 11 of the 13 temporal operators, comparison of records is straight-forward.  However, the `Before`/`After` operators have a slight twist.

Imagine events 1-1-2-1-2-1.  In my mind, three 1's come before a 2 and two 1's come after a 2.  Accordingly:

- When comparing L **before** R, the temporal operator compares L against the **LAST** occurrence of R per person
- When comparing L **after** R, the temporal operator compares L against the **FIRST** occurrence of R per person

If we're looking for events in L that occur before events in R, then any event in L that occurs before the last event in R technically meet the comparison of "before".  The reverse is true for after: all events in L that occur after the first event in R technically occur after R.

```ConceptQL
# All MIs that occurred before a patient's __last__ case of diabetes (250.01)
[
  "before",
  {
    "left": [
      "icd9",
      "412"
    ],
    "right": [
      "icd9",
      "250.01"
    ]
  }
]
```

If this is not the behavior you desire, use one of the sequence operators to select which event in R should be the one used to do comparison

```ConceptQL
# All MIs that occurred before a patient's __first__ case of diabetes (250.01)
[
  "before",
  {
    "left": [
      "icd9",
      "412"
    ],
    "right": [
      "first",
      [
        "icd9",
        "250.01"
      ]
    ]
  }
]
```

### Temporal Comparison Improvements

Sometimes it is difficult to reason through `Time Window` (described below) when working with temporal comparison operators.  It would be nice if a more intuitive language could be used to describe some common temporal relationships.

We've added a few parameters, primarily for the `Before` and `After` operators, that will help with temporal comparisons.

#### New Parameters

- `within`
    - Takes same date adjustment format as `time_window`, e.g. 30d or 2m or 1y-3d
    - The start_date and end_date of the RHS are adjusted out in each direction by the amount specified and the event must pass the original temporal comparison and then fall within the window created by the adjustment
- `at_least`
    - Takes same date adjustment format as `time_window`, e.g. 30d or 2m or 1y-3d
- `occurrences`
    - Takes an whole number

Let's see them in action:

**Prescriptions After a Office Visit** - Find all prescriptions of interest occurring within three days after an office visit

```ConceptQL
[
    "after", {
        "left": [
            "ndc", "61392070054", "65084025214", "65726040125", { "label": "Prescriptions of Interest" }
        ],
        "right": [
            "cpt", "99214", { "label": "Office Visit" }
        ],
        "within": "3d"
    }
]
```

Walk through of example above:

- Pull some prescriptions of interest into LHS
- Pull some office visits into RHS
- Compare LHS against RHS, enforcing that the LHS' start_date falls after the RHS' end_date
- Enforce that any remaining LHS' start_date falls within an RHS's (start_date - 3 days) and (end_date + 3 days)

**Find all Heart Attacks Probably Resulting in Death** -- Does anyone die within a year of a heart attack?

```ConceptQL
[
    "before", {
        "left": [
            "icd9", "410.00", "410.01", "410.10", "410.11"
        ],
        "right": [
            "death"
        ],
        "within": "1y"
    }
]
```

Walk through of example above:

- Pull hospitalizations into LHS
- Pull death records into RHS
- Compare LHS against RHS, enforcing that the LHS' end_date falls before the RHS' start_date
- Enforce that any remaining LHS row's end_date falls within an RHS row's (start_date - 1 year) and (end_date + 1 year)


```ConceptQL
# Multiple Myeloma algorithm -- Select all diabetes diagnoses that are preceded by at least 3 other diabetes diagnoses within 90 days of each other.
[
    "after", {
        "left": [
            "icd9",
            "250.00",
            { "label": "Diabetes Dx" }
        ],
        "right": [
            "recall",
            "Diabetes Dx"
        ],
        "occurrences": 3,
        "within": "90d"
    }
]
```

Walk through of example above:

- Pull diabetes diagnoses into LHS
- Pull same set of diagnoses into RHS
- Keep all LHS rows where LHS' start_date falls between RHS' end_date and (end_date + 90 days)
- Use a window function to group LHS by matching RHS row and sort group by date, then number each LHS row
- Keep only LHS rows that have a number greater than 3
- Dedupe LHS rows on output

```ConceptQL
# Find all diagnosis of heart attack at least 1 week after a diagnosis of diabetes
[
    "after", {
        "left": [
            "icd9",
            "410.00", "410.01", "410.10", "410.11",
            { "label": "Heart Attack Dx" }
        ],
        "right": [
            "icd9", "250.01", { "label": "Diabetes Dx"}
        ],
        "at_least": "1w"
    }
]
```

This example illustrates how `at_least` works.

#### Considerations

Currently, temporal comparisons are done with an inner join between the LHS relation and the RHS relation.  This has some interesting effects:

- If more than one RHS row matches with an LHS row, multiple copies of the LHS row will end up in the downstream records
    - Should we limit the LHS to only unique rows, essentially de-duping the downstream records?
- If the same row appears in both the LHS and RHS relation, it is likely the row will match itself (e.g. a row occurs during itself and contains itself etc.)
    - This is a bit awkward and perhaps we should skip joining rows against each other if they are identical (i.e. have the same `criterion_id` and `criterion_type`)?

### `Time Window` Operator

There are situations when the date columns associated with a record should have their values shifted forward or backward in time to make a comparison with another set of dates.  This is where the `Time Window` operator is used.  It has the following properties:

- Takes 2 arguments
    - First argument is the stream on which to operate
    - Second argument is a hash with two keys: \[:start, :end\] each with a value in the following format:  "(-?\d+\[dmy\])+"
        - Both start and end must be defined, even if you are only adjusting one of the dates
    - Some examples
        - 30d => 30 days
        - 20 => 20 days
        - d => 1 day
        - 1y => 1 year
        - -1m => -1 month
        - 10d3m => 3 months and 10 days
        - -2y10m-3d => -2 years, +10 months, -3 days
    - The start or end value can also be '', '0', or nil
        - This will leave the date unaffected
    - The start or end value can also be the string 'start' or 'end'
        - 'start' represents the start_date for each record
        - 'end' represents the end_date for each record
        - See the example below

```ConceptQL
# All Diagnoses of Diabetes (ICD-9 250.01) within 30 days of an MI
[
  "during",
  {
    "left": [
      "icd9",
      "250.01"
    ],
    "right": [
      "time_window",
      [
        "icd9",
        "412"
      ],
      {
        "start": "-30d",
        "end": "30d"
      }
    ]
  }
]
```

```ConceptQL
# Shift the window for all MIs back by 200 years
[
  "time_window",
  [
    "icd9",
    "412"
  ],
  {
    "start": "-200y",
    "end": "-200y"
  }
]
```

```ConceptQL
# Expand the dates for all MIs to a window ranging from 2 months and 2 days prior to 1 year and 3 days after the MI
[
  "time_window",
  [
    "icd9",
    "412"
  ],
  {
    "start": "-2m-2d",
    "end": "3d1y"
  }
]
```

```ConceptQL
# Collapse all 412 date ranges down to just the date of admission by leaving start_date unaffected and setting end_date to start_date
[
  "time_window",
  [
    "icd9",
    "412"
  ],
  {
    "start": "",
    "end": "start"
  }
]
```

```ConceptQL
# Nonsensical, but allowed: swap the start_date and end_date for a range
[
  "time_window",
  [
    "icd9",
    "412"
  ],
  {
    "start": "end",
    "end": "start"
  }
]
```

#### Temporal Operators and Person Streams

Person streams carry a patient's date of birth in their start and end date columns.  This makes them almost useless when they are part of the L stream of a temporal operator.  But person streams are useful as the R stream.  By `Time Window`ing the patient's date of birth, we can filter based on the patient's age like so:

```ConceptQL
# All MIs that occurred after a male patient's 50th birthday
[
  "after",
  {
    "left": [
      "icd9",
      "412"
    ],
    "right": [
      "time_window",
      [
        "gender",
        "Male"
      ],
      {
        "start": "50y",
        "end": "50y"
      }
    ]
  }
]
```

### `Episode` Operator

There are rare occasions when we'd like to stitch a set of events together into a span of time, such as a set of prescriptions events into a span of time we'd consider a patient to be taking a certain medication.  ConceptQL provides the `Episode` operator for such an occasion.

```ConceptQL
[ "episode", ["icd9", "250.00"], { "gap_of": "90" } ]
```

One side-effect of this operator is that the `criterion_domain` is set to "episode" and each row no longer contains a reference back to a `criterion_id` or `criterion_table` because one or more records are folded into a single row after passing through the episode operator.  Often, the episode operator is best-suited to act as the RHS of a temporal operator.

## Inline-Filter Operators

There are a couple of operators that filter an incoming stream before passing it along.

### `Place of Service Filter` Operator

Often in claims data, an event is reported with a place of service via the CMS place of service codes, such as "inpatient hospital" (21) or "outpatient hospital" (22).  For these kinds of queries, ConceptQL has the `Place of Service Filter`

```ConceptQL
["place_of_service_filter", 22, ["icd9", "250.00"]]
```

Our sample data for the examples in this document does not contain any place of service information so there are no records after applying this filter.

### `Provenance` Operator

For better or worse, provenance, or rather information about the origin of claims data, is some times an important factor in research algorithms.  Often, paper authors will describe using "inpatient records", by which they mean using claims that come from "the inpatient file" from a set of claims data.  [GDM](https://github.com/outcomesinsights/generalized_data_model#contexts) tracks the provenance of data as part of its ETL process, and ConceptQL includes an operator to select rows that have a particular provenance, aptly called `Provenance`.

```ConceptQL
["provenance", "inpatient", [ "icd9", "250.00" ]]
```

### `Provider Filter` Operator

There are times when we'd like to captures events only when a particular provider specialty was involved.  ConceptQL provides the `Provider Filter` operator for this.  This operator is a bit bare-bones at the moment in that it requires users to enter in the concept ID of the specialty they are seeking, rather than providing a list of known specialties.

```ConceptQL
[ "provider_filter", [ "icd9", "250.00"], { "specialties": "12301023" }]
```

Our sample data for the examples in this document does not contain any provider specialty information so there are no records after applying this filter.

## `One In Two Out` Operator

A very common pattern in algorithms is to consider a condition to be valid if:
- the condition is seen just once in the inpatient file, or
- the condition is present twice in the outpatient file, with
  - a minimum separation, normally of a 30 days, between the two occurrences

We have created an operator that handles this pattern: `One In Two Out`

```ConceptQL
# First of diabetes diagnoses, either found once in the inpatient file, or twice in the outpatient file with a minimum of 30 days between outpatient diagnoses
["one_in_two_out", ["icd9", "250.00"], { "outpatient_minimum_gap": "30d"}]
```

The `One In Two Out` operator yields a single row per patient.  The row is the earliest confirmed event from the operator's upstream set of events.

The `One In Two Out` operator uses the file from which a row came from to determine if the row represents an "inpatient" record or an "outpatient" record.  The place of service associated with a record is not taken into account.  Nothing about the associated visit is considered either.

`condition_occurrence` rows with provenance related to of "inpatient" files are considered inpatient records.  All other records are considered outpatient.

Non-`condition_occurrence` rows are removed from the stream.

In order to simplify how sets of inpatient and outpatient records are compared to each other temporally, we collapse each incoming row's date range to a single date.  Users can choose which date to use for both inpatient and outpatient records.

- Inpatient Length of Stay
    - Enforces a minimum length of stay for inpatient records
    - If given a whole number greater than 0, requires that the patient had been hospitalized for at least that many days
    - Optional
    - Default: empty
    - If left empty, length of stay is ignored
    - Length of Stay (LOS) is calculated as:
        - If (end_date - start_date) < 2, then LOS is 1
        - else LOS is (end_date - start_date) + 1
- Inpatient Return Date
    - Determines which date from an inpatient record should be used as the date in which the associated condition "occurred"
    - Options
        - Admit Date
        - Discharge Date
    - Optional
    - Defaults to discharge date (end_date of the given condition_occurrence)
        - The discharge date is preferred over the admit date because only at discharge can we say for certain a patient was diagnosed with a given condition.  We cannot be certain a patient had the condition at the time of admission
- Outpatient Minimum Gap
    - Requires that the second, confirming outpatient diagnosis must occur at least this many days after the initial diagnosis
    - Uses same time adjustment syntax as `time_window`, e.g. 1d3m10y
    - Required
    - Default: 30d
- Outpatient Maximum Gap
    - Requires that the second, confirming outpatient diagnosis must occur at within this many days after the initial diagnosis
    - Uses same time adjustment syntax as `time_window`, e.g. 1d3m10y
    - Optional
    - Default: empty
    - When empty, the confirming diagnosis may occur at any time after the minimum_gap to be considered valid
    - This option is useful when attempting to limit confirming diagnoses for acute diseases, e.g. if attempting to find confirmation of the flu, it would be advisable to set this option in order to limit confirmation to distinct periods when a patient had the flu
- Outpatient Event to Return
    - Determines which event return should two outpatient records meet all criteria
        - In most situations, using the initial outpatient event is desired, particularly when the algorithm is used to record an exposure of interest or outcome
        - However, returning the initial outpatient event when the algorithm is used to determine an index event can introduce immortal time bias.  In these cases, using the confirming event will avoid immortal time bias
    - Options
        - Initial Event
        - Confirming Event
    - Optional
    - Defaults to Initial Event

## `Person Filter` Operator

Often we want to filter out a set of records by people.  For instance, say we wanted to find all MIs for all males.  We'd use the `Person Filter` operator for that.  Like the `Except` operator, it takes a left-hand stream and a right-hand stream.

Unlike the `Except` operator, the `Person Filter` operator will use all types of all streams in the right-hand side to filter out records in all types of all streams on the left hand side.

```ConceptQL
# All MI Conditions for people who are male
[
  "person_filter",
  {
    "left": [
      "icd9",
      "412"
    ],
    "right": [
      "gender",
      "Male"
    ]
  }
]
```

But we can get crazier.  The right-hand side doesn't have to be a person stream.  If a non-person stream is used in the right-hand side, the person_filter will cast all right-hand streams to person first and use the union of those streams:

```ConceptQL
# All MI Conditions for people who had an office visit at some point in the data
[
  "person_filter",
  {
    "left": [
      "icd9",
      "412"
    ],
    "right": [
      "cpt",
      "99214"
    ]
  }
]
```

```ConceptQL
# All MI Conditions for people who had an office visit at some point in the data (an explicit representation of what's happening in the diagram above)
[
  "person_filter",
  {
    "left": [
      "icd9",
      "412"
    ],
    "right": [
      "person",
      [
        "cpt",
        "99214"
      ]
    ]
  }
]
```

```ConceptQL
# All MI Conditions for people who are Male OR had an office visit at some point in the data
[
  "person_filter",
  {
    "left": [
      "icd9",
      "412"
    ],
    "right": [
      "union",
      [
        "cpt",
        "99214"
      ],
      [
        "gender",
        "Male"
      ]
    ]
  }
]
```

And don't forget the left-hand side can have multiple types of streams:

```ConceptQL
# Yields two streams: a stream of all MI Conditions for people who are Male and a stream of all office visit Procedures for people who are Male
[
  "person_filter",
  {
    "left": [
      "union",
      [
        "icd9",
        "412"
      ],
      [
        "cpt",
        "99214"
      ]
    ],
    "right": [
      "gender",
      "Male"
    ]
  }
]
```

## `Co-Reported` Operator

Claims data often reports diagnoses on the same "line" as a procedure.  This is done for billing reasons, essentially the provider is saying "I preformed this procedure due to these conditions present in the patient".  ConceptQL has an operator that specifically targets this kind of relationship: `Co-Reported`

The operator takes two or more streams.  Events in each stream must be reported at the same time in order to be passed through the operator.  In the case of [GDM](https://github.com/outcomesinsights/generalized_data_model) this means that events that share the same [context](https://github.com/outcomesinsights/generalized_data_model#contexts) ID.


```ConceptQL
# Diabetes diagnosis reported as part the reason for an office visit
[ "co_reported", [ "icd9", "250.00" ], ["cpt", "99214" ] ]
```

Note that both the diagnosis and procedure are pass on through the operator.

## `label` Option and Its Features

Any ConceptQL operator can be assigned a label.  The label simply provides a way to apply a brief description to an operator, generally, what kind of records the operator is producing.  

Any operator with a `label` inserts its `label` into the set of records.

For instance, here are some diabetes diagnoses with a label applied:

```ConceptQL{all_keys: true}
["icd9", "250.00", "label": "diabetes"]
```

The most recent upstream `label` is the one that is output:

```ConceptQL{all_keys: true}
["first", ["icd9", "250.00", "label": "won't show"], "label": "1st diabetes"]
```

The idea behind this is to create hints about what is being output:

```ConceptQL{all_keys: true}
["first", ["union", ["icd9", "250.00", "label": "diabetes"], ["icd9", "401.9", "label": "hypertension"]]]
```


### `Recall` Operator

If a algorithm is particularly complex, or has a stream of records that are used more than once, it can be helpful to break the algorithm into a set of sub-algorithms.  This can be done using the `label` options and the `Recall` operator.  Any operator that has a label can be accessed via the `Recall` operator.

- Takes 1 argument
    - The "label" of an operator from which you'd like to pull the exact same set of records

A stream must be have a label applied to it before `Recall` can use it.

```ConceptQL
# Save away a stream of records to build the 1 inpatient, 2 outpatient pattern used in claims data algorithms
[["one_in_two_out",["except",{"left":["union",["icd9","330.0","330.1","330.2","330.3","330.8","330.9","331.0","331.11","331.19","331.2","331.3","331.4","331.5","331.6","331.7","331.81","331.82","331.83","331.89","331.9","332.0","333.4","333.5","333.7","333.71","333.72","333.79","333.85","333.94","334.0","334.1","334.2","334.3","334.4","334.8","334.9","335.0","335.10","335.11","335.19","335.20","335.21","335.22","335.23","335.24","335.29","335.8","335.9","338.0","340","341.0","341.1","341.20","341.21","341.22","341.8","341.9","345.00","345.01","345.10","345.11","345.2","345.3","345.40","345.41","345.50","345.51","345.60","345.61","345.70","345.71","345.80","345.81","345.90","345.91","347.00","347.01","347.10","347.11","649.40","649.41","649.42","649.43","649.44","768.70","768.71","768.72","768.73","780.31","780.32","780.33","780.39","784.3"],["icd10cm","E75.00","E75.01","E75.02","E75.09","E75.10","E75.11","E75.19","E75.23","E75.25","E75.26","E75.29","E75.4","F84.2","G10","G11.0","G11.1","G11.2","G11.3","G11.4","G11.8","G11.9","G12.0","G12.1","G12.20","G12.21","G12.22","G12.23","G12.24","G12.25","G12.29","G12.8","G12.9","G13.2","G13.8","G20","G21.4","G24.01","G24.02","G24.09","G24.2","G24.8","G25.4","G25.5","G25.81","G30.0","G30.1","G30.8","G30.9","G31.01","G31.09","G31.1","G31.2","G31.81","G31.82","G31.83","G31.84","G31.85","G31.89","G31.9","G32.81","G35","G36.1","G36.8","G36.9","G37.0","G37.1","G37.2","G37.3","G37.4","G37.5","G37.8","G37.9","G40.001","G40.009","G40.011","G40.019","G40.101","G40.109","G40.111","G40.119","G40.201","G40.209","G40.211","G40.219","G40.301","G40.309","G40.311","G40.319","G40.401","G40.409","G40.411","G40.419","G40.501","G40.509","G40.801","G40.802","G40.803","G40.804","G40.811","G40.812","G40.813","G40.814","G40.821","G40.822","G40.823","G40.824","G40.89","G40.901","G40.909","G40.911","G40.919","G40.A01","G40.A09","G40.A11","G40.A19","G40.B01","G40.B09","G40.B11","G40.B19","G47.411","G47.419","G47.421","G47.429","G80.3","G89.0","G91.0","G91.1","G91.2","G91.3","G91.4","G91.8","G91.9","G93.7","G93.89","G93.9","G94","O99.350","O99.351","O99.352","O99.353","O99.354","O99.355","P91.60","P91.61","P91.62","P91.63","R41.0","R41.82","R47.01","R56.00","R56.01","R56.1","R56.9"],{"label":"neuro dxs"}],"right":["co_reported",["recall","neuro dxs"],["drg","020","021","022","023","024","025","026","027","028","029","030","031","032","033","034","035","036","037","038","039","040","041","042","052","053","054","055","056","057","058","059","060","061","062","063","064","065","066","067","068","069","070","071","072","073","074","075","076","077","078","079","080","081","082","083","084","085","086","087","088","089","090","091","092","093","094","095","096","097","098","099","100","101","102","103"]]}],{"outpatient_event_to_return":"Confirming Event","outpatient_minimum_gap":"30d","inpatient_return_date":"Discharge Date","outpatient_maximum_gap":"365d"}]]
```

## Appendix A - Additional Operators

### `Vocabulary` Operator

A `Vocabulary` operator is any selection operator that selects records based on codes from a specific vocabulary.  Below is a list of the most common vocabulary operators available in ConceptQL:

| Operator Name | Stream Type | Arguments | Returns |
| ---- | ---- | --------- | ------- |
| cpt4  | procedure_occurrence | 1 or more CPT codes | All records whose source_value match any of the CPT codes |
| icd9cm | condition_occurrence | 1 or more ICD-9CM codes | All records whose source_value match any of the ICD-9 codes |
| icd9_procedure | procedure_occurrence | 1 or more ICD-9 procedure codes | All records whose source_value match any of the ICD-9 procedure codes |
| icd10cm | condition_occurrence | 1 or more ICD-10 | All records whose source_value match any of the ICD-10 codes |
| hcpcs  | procedure_occurrence | 1 or more HCPCS codes | All records whose source_value match any of the HCPCS codes |
| gender | person | 1 or more gender concept_ids | All records whose gender_concept_id match any of the concept_ids|
| loinc | observation | 1 or more LOINC codes | All records whose source_value match any of the LOINC codes |
| race | person | 1 or more race concept_ids | All records whose race_concept_id match any of the concept_ids|
| rxnorm | drug_exposure | 1 or more RxNorm IDs | All records whose drug_concept_id match any of the RxNorm IDs|
| snomed | condition_occurrence | 1 or more SNOMED codes | All records whose source_value match any of the SNOMED codes |

### More Temporal Operators

#### `During` Operator

The `During` operator is a [Temporal Operator](#temporal-comparison-operators).  For each person, records on the left hand side are compared to records on the right hand side.  It only passes along those left hand records whose date range is fully, and inclusively, contained within a right hand record's date range.

#### `Contains` Operator

The `Contains` operator is a [Temporal Operator](#temporal-comparison-operators).  For each person, records on the left hand side are compared to records on the right hand side.  It only passes along those left hand records whose date range fully, and inclusively, contains a right hand record's date range.

### More Person Operators

Person operators generate person records, or records that are derived from the table containing patient demographics.  The start_date and end_date for a person-based record is the patient's birth date, as explained in more detail [in temporal operators and person streams](#temporal-operators-and-person-streams).

#### `Gender` Operator

This [person operator](#more-person-operators) selects people by gender.  Currently, available genders are Male, Female, or Unknown.

#### `Race` Operator

This [person operator](#more-person-operators) selects people by race.  Available races are defined in the Race vocabulary.

### `Death` Operator

This operator pulls all death records from the death table.

## Appendix B - Algorithm Showcase

Here are some algorithms from [OMOP's Health Outcomes of Interest](http://omop.org/HOI) turned into ConceptQL statements to give more examples.  I truncated some of the sets of codes to help ensure the diagrams didn't get too large.

### Acute Kidney Injury - Narrow Definition and diagnostic procedure

- ICD-9CM of 584
- AND
    - ICD-9 procedure codes of 39.95 or 54.98 within 60 days after diagnosis
- AND NOT
    - A diagnostic code of chronic dialysis any time before initial diagnosis
        - V45.1, V56.0, V56.31, V56.32, V56.8

```ConceptQL
[
  "during",
  {
    "left": [
      "except",
      {
        "left": [
          "icd9",
          "584"
        ],
        "right": [
          "after",
          {
            "left": [
              "icd9",
              "584"
            ],
            "right": [
              "icd9",
              "V45.1",
              "V56.0",
              "V56.31",
              "V56.32",
              "V56.8"
            ]
          }
        ]
      }
    ],
    "right": [
      "time_window",
      [
        "icd9_procedure",
        "39.95",
        "54.98"
      ],
      {
        "start": "0",
        "end": "60d"
      }
    ]
  }
]
```

### Mortality after Myocardial Infarction #3

- Person Died
- And Occurrence of 410\* prior to death
- And either
    - MI diagnosis within 30 days prior to 410
    - MI therapy within 60 days after 410

```ConceptQL
[
  "during",
  {
    "left": [
      "before",
      {
        "left": [
          "icd9",
          "410*"
        ],
        "right": [
          "death"
        ]
      }
    ],
    "right": [
      "union",
      [
        "time_window",
        [
          "union",
          [
            "cpt",
            "0146T",
            "75898",
            "82554",
            "92980",
            "93010",
            "93233",
            "93508",
            "93540",
            "93545"
          ],
          [
            "icd9_procedure",
            "00.24",
            "36.02",
            "89.53",
            "89.57",
            "89.69"
          ],
          [
            "loinc",
            "10839-9",
            "13969-1",
            "18843-3",
            "2154-3",
            "33204-9",
            "48425-3",
            "49259-5",
            "6597-9",
            "8634-8"
          ]
        ],
        {
          "start": "-30d",
          "end": "0"
        }
      ],
      [
        "time_window",
        [
          "union",
          [
            "cpt",
            "0146T",
            "75898",
            "82554",
            "92980",
            "93010",
            "93233"
          ],
          [
            "icd9_procedure",
            "00.24",
            "36.02",
            "89.53",
            "89.57",
            "89.69"
          ]
        ],
        {
          "start": "",
          "end": "60d"
        }
      ]
    ]
  }
]
```

## Appendix C - History of ConceptQL and Its Evolution

ConceptQL was originally developed to query data from the [OMOP Common Data Model (CDM) v4.0](https://github.com/OHDSI/CommonDataModel/releases/tag/v4).  This meant that ConceptQL was able to take simple statements like `[ "icd9", "412" ]` and determine the proper table to query (in this case `condition_occurrence`) along with the correct source_code and vocabulary_id to search for within that table.

As the OMOP CDM continued to evolve and as its ETL requirements continued to spiral, [Outcomes Insights, Inc](https://outins.com) developed the [GDM](https://github.com/outcomesinsights/generalized_data_model) and ConceptQL was adapted to support querying both data models.  Eventually support for OMOP's CDM was removed from ConceptQL because it was no longer used in any production applications of ConceptQL.  However, this experience has demonstrated that ConceptQL can be adapted to support other data models should the need arise.

ConceptQL was originally implemented to work against PostgreSQL, but was adapted to work against MSSQL, Oracle, and Impala.  We have since refocused ConceptQL to work against PostgreSQL, but we have shown that, with a modest amount of effort, ConceptQL can be made to support most RDBMS systems that support most features found in [SQL:2003](https://en.wikipedia.org/wiki/SQL:2003), such as window functions.  Most SQL generated by ConceptQL is fairly "vanilla" in that it does not rely on special quirks or query hints specific to a particular RDBMS in order to function.
