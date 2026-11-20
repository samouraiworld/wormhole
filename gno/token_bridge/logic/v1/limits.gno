package logic

// The limits' windows: amounts counted in 25 hourly buckets of block time, the
// current hour and the 24 before it. An amount fits if amount <= limit - sum.
// The sum never exceeds the limit, so this cannot wrap, as sum + amount could.
// The amounts counted in any 24 hours all lie in the buckets the last of them
// was checked against, so no more than the limit is counted in any 24 hours.

const (
	windowHours = 25
	hourSeconds = 3600
)

// window holds, for each bucket, the hour it counts and what it counted. An
// hour's bucket is its index modulo windowHours; a bucket left by an older
// hour counts nothing.
type window struct {
	hours  [windowHours]int64
	counts [windowHours]int64
}

// currentHour is the block time's hour index.
func currentHour() int64 {
	return blockTime() / hourSeconds
}

// sum returns what the window counted in hour and the 24 before it.
func (w *window) sum(hour int64) int64 {
	var total int64
	for i := 0; i < windowHours; i++ {
		if w.hours[i] > hour-windowHours {
			total += w.counts[i]
		}
	}
	return total
}

// fits reports whether amount fits under limit in hour.
func (w *window) fits(hour, amount, limit int64) bool {
	return amount <= limit-w.sum(hour)
}

// count adds to hour's bucket an amount that fits, which it starts afresh if
// an older hour left it.
func (w *window) count(hour, amount int64) {
	i := hour % windowHours
	if w.hours[i] != hour {
		w.hours[i], w.counts[i] = hour, 0
	}
	w.counts[i] += amount
}
