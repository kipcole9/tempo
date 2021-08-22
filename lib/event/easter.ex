defmodule Tempo.Event.Easter do
  import Kernel, except: [floor: 1]
  import Astro.Math, only: [mod: 2, floor: 1]

  @doc """
  [epact](https://en.wikipedia.org/wiki/Epact)

  `epacts` are an approximation of the lunar phases.
  These are based upon the idea that new moons occur
  on about the same day of the solar year in a cycle
  of 19 years. This is referred to as the metonic cycle.
  """

  # Full moon day of a lunar cycle
  @paschal_full_moon_day_in_lunar_cycle 14

  # The difference between a common year of 365 days
  # and that of a 12 lunar months of 29.5 days
  @days_diff_between_common_year_and_lunar_year 11

  def gregorian_easter(gregorian_year, calendar \\ Calendar.ISO)
      when is_integer(gregorian_year) do
    paschal_moon = gregorian_paschal_moon(gregorian_year, calendar)
    Cldr.Calendar.Kday.kday_after(paschal_moon, Cldr.Calendar.sunday())
  end

  def gregorian_paschal_moon(gregorian_year, calendar \\ Calendar.ISO)
      when is_integer(gregorian_year) do
    century = floor(gregorian_year / 100) + 1
    metonic_phase = metonic_phase(gregorian_year)
    leap_year_adjustment = leap_year_adjustment(century)
    correction = correction(century)
    epact = epact(metonic_phase)
    shifted_epact = mod(epact - leap_year_adjustment + correction, 30)
    adjusted_epact = adjusted_epact(shifted_epact, metonic_phase)

    Date.new!(gregorian_year, 4, 19)
    |> Cldr.Calendar.date_to_iso_days()
    |> Kernel.-(adjusted_epact)
    |> trunc
    |> Cldr.Calendar.date_from_iso_days(Cldr.Calendar.Gregorian)
    |> Date.convert!(calendar)
  end

  # Full moon occurs on the 14th day of the
  # lunar cycle
  def epact(metonic_phase) do
    @paschal_full_moon_day_in_lunar_cycle +
      (@days_diff_between_common_year_and_lunar_year * metonic_phase)
  end

  def metonic_phase(gregorian_year) do
    mod(gregorian_year, 19)
  end

  # 3 out of 4 century years the Gregoian leap
  # year rule causes a shift of 1 day forward
  # in the date of the paschal new moon
  def leap_year_adjustment(century) do
     floor(3 / 4 * century)
  end

  def correction(century) do
    floor(1 / 25 * (5 + 8 * century))
  end

  defp adjusted_epact(shifted_epact, metonic_phase)
      when shifted_epact == 0 or (shifted_epact == 1 and 10 < metonic_phase) do
    shifted_epact + 1
  end

  defp adjusted_epact(shifted_epact, _year_mod19) do
    shifted_epact
  end

  def orthodox_easter(_year) do

  end

end