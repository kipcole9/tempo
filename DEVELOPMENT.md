## Notes

### On Implicit and Explicit intervals

An implicit interval, such as `2022` is equalivent to the explicit interval `2022-01/12`. The transformation proceeds as follows:

1. Enumeration for implicit intervals occurs at the next hightest zoom level (greater resolution). In this case is is months.
2. The end of the interval is a closed at month 12. 
3. Therefore we can say the implicit interval is closed and equivalent to the set `{2022-01, 2022-02, ..., 2022-12}`

### On conversion between explicit and implicit intervals

* Implicit intervals can always be converted to explicit intervals or a set of explicit intervals
* Not all explcit intervals can be converted to implicit ones.
* The explicit interval for `2022` is `2022/2022` since it is a closed interval of `[2022]`


