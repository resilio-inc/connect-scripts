from sys import stdout, stderr
import logging
import os

IS_DEBUG = os.getenv("DEBUG") == "1"


class Logger:
    FORMATTER = logging.Formatter('[ %(asctime)s ][ %(levelname)s ] %(message)s')
    LOG_LEVEL = logging.DEBUG if IS_DEBUG else logging.INFO

    def __init__(self):
        # info logger
        self.logger = logging.getLogger("info")
        self.logger.setLevel(self.LOG_LEVEL)

        # error logger
        self.error_logger = logging.getLogger("error")
        self.error_logger.setLevel(logging.ERROR)

        # create stdout stream handler
        self.stdout_handler = logging.StreamHandler(stream=stdout)
        self.stdout_handler.setFormatter(self.FORMATTER)
        self.stdout_handler.setLevel(self.LOG_LEVEL)

        self.logger.addHandler(self.stdout_handler)

        # create stderr stream handler
        self.stderr_handler = logging.StreamHandler(stream=stderr)
        self.stderr_handler.setFormatter(self.FORMATTER)
        self.stderr_handler.setLevel(logging.ERROR)

        self.error_logger.addHandler(self.stderr_handler)

    def error(self, *args, backtrace=False):
        self.error_logger.error(*args, exc_info=backtrace)

    def info(self, *args, backtrace=False):
        self.logger.info(*args, exc_info=backtrace)

    def debug(self, *args, backtrace=False):
        self.logger.debug(*args, exc_info=backtrace)

    def warning(self, *args, backtrace=False):
        self.logger.warning(*args, exc_info=backtrace)


logger = Logger()
