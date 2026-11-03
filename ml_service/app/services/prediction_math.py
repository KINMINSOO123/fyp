from math import ceil, floor


def round_half_away_from_zero(value: float) -> int:
    if value >= 0:
        return floor(value + 0.5)

    return ceil(value - 0.5)