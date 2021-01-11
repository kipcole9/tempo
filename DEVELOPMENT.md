## Notes

* When parsing clock time, ommitted higher order is set to zero. This does not apply to dates.

* Groups need to be resolved to either an implicit interval (ie like a month, week or day - even quarter and season) or to an explicit interval

* Unspecified components need to be resolved to .... ?

* When parsing an interval some heuristic is required to resolve some forms like:
  * 2020-01-01/02 would parse the "02" as a month when it needs to be interpreted as a day. This may be the other exception?

* Support of fractional components in duration? (section 11.4 in Part 2)

*