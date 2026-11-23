import json
from decimal import Decimal, InvalidOperation


def _response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def _to_number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float, str)):
        raise ValueError
    number = Decimal(str(value))
    if not number.is_finite():
        raise ValueError
    return number


def lambda_handler(event, _context):
    try:
        payload = json.loads(event.get("body") or "{}")
        a = _to_number(payload["a"])
        b = _to_number(payload["b"])
    except (json.JSONDecodeError, KeyError, TypeError, ValueError, InvalidOperation, AttributeError):
        return _response(400, {"error": 'Envie um JSON com campos numericos "a" e "b", ex.: {"a": 1, "b": 2}'})

    result = a + b
    as_json = int(result) if result == result.to_integral_value() else float(result)
    return _response(200, {"a": payload["a"], "b": payload["b"], "result": as_json})
