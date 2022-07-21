#!/usr/bin/env python3
import traceback
from typing import Optional

import time

from dt_device_utils import get_device_hardware_brand, DeviceHardwareBrand
ROBOT_HARDWARE = get_device_hardware_brand()

if ROBOT_HARDWARE is DeviceHardwareBrand.JETSON_NANO:
    import Jetson.GPIO as GPIO
    GPIO_OUT = -1
    GPIO_IN = -1

elif ROBOT_HARDWARE in [DeviceHardwareBrand.RASPBERRY_PI, DeviceHardwareBrand.RASPBERRY_PI_64]:
    import RPi.GPIO as GPIO
    GPIO_OUT = 5
    GPIO_IN = 6

elif ROBOT_HARDWARE is DeviceHardwareBrand.VIRTUAL:
    exit(99)

else:
    raise Exception("Undefined Hardware!")


def main():
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(GPIO_IN, GPIO.IN)
    GPIO.setup(GPIO_OUT, GPIO.OUT)

    def jumper_connected() -> Optional[bool]:
        """
        This function sends a sequence of bits to GPIO_OUT and expects it in from GPIO_IN.
        It keeps checking this until GPIO_IN is always at 0 (jumper is off) or the sequence
        is successfully transferred from GPIO_OUT to GPIO_IN (jumper is on).

        This is needed because sometimes the GPIO_IN reports 1 even with no jumper on.

        Returns:
            True if the jumper is detected, False if the jumper is not detected, None if inconclusive.

        """
        sequence_out = [1, 0, 1, 1, 0]
        sequence_in = []
        for bit in sequence_out:
            # set out pin
            GPIO.output(GPIO_OUT, bit)
            # wait 500ms
            time.sleep(0.5)
            # read in pin
            sequence_in.append(int(GPIO.input(GPIO_IN)))
        print(f"Sequence {sequence_out} -> {sequence_in}")

        # identical sequences => jumper detected
        if sequence_in == sequence_out:
            return True
        # zero sequence => jumper NOT detected
        if sum(sequence_in) == 0:
            return False
        # different sequences => inconclusive test
        print("> Inconclusive test")
        return None

    # run sequence test until conclusive test or 2m elapsed
    stime = time.time()
    timeout = 2 * 60
    result = None

    # noinspection PyBroadException
    try:
        while time.time() - stime < timeout and result is None:
            result = jumper_connected()
            # wait 1s
            time.sleep(1)
    except BaseException:
        traceback.print_last()
        # clean up
        GPIO.cleanup()

    # default behavior: AP mode (always inconclusive tests)
    if result is None:
        print(f"The test was inconclusive for {timeout}s, assuming jumper is present")
        result = 1

    # exit with 0 to signal jumper is missing
    exit(int(result))


if __name__ == '__main__':
    main()
