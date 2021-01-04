#!/usr/bin/python

# From https://stackoverflow.com/a/48551853
class FilterModule(object):
    def filters(self):
        return {
            'bitwise_and': self.bitwise_and
        }

    def bitwise_and(self, a, b):
        return (a & b)
