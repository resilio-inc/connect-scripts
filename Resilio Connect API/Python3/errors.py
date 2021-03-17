class ApiError(Exception):
    pass


class ApiConnectionError(ApiError):
    pass


class ApiUnauthorizedError(ApiError):
    pass
