import argparse
import unittest

from swift_build_support.cmake import CMakeOptions
from swift_build_support.products.cmake_product import CMakeProduct


class DummyCMakeProduct(CMakeProduct):
    @classmethod
    def is_build_script_impl_product(cls):
        return False

    @classmethod
    def is_before_build_script_impl_product(cls):
        return False

    @classmethod
    def get_dependencies(cls):
        return []

    def should_build(self, host_target):
        return True

    def build(self, host_target):
        raise NotImplementedError

    def should_test(self, host_target):
        return self.args.test_dummy

    def test(self, host_target):
        raise NotImplementedError

    def should_install(self, host_target):
        return False

    def install(self, host_target):
        raise NotImplementedError


class CMakeProductTestCase(unittest.TestCase):
    def make_product(self, *, test_dummy=False, extra_cmake_options=None):
        args = argparse.Namespace(
            verbose_build=False,
            extra_cmake_options=extra_cmake_options or [],
            test_dummy=test_dummy,
        )
        product = DummyCMakeProduct(
            args=args,
            toolchain=argparse.Namespace(cmake='cmake'),
            source_dir='/tmp/src',
            build_dir='/tmp/build',
        )
        product.cmake_options = CMakeOptions()
        product._host_target_for_build = 'macosx-x86_64'
        return product

    def test_sets_build_testing_off_when_product_tests_are_disabled(self):
        product = self.make_product(test_dummy=False)

        product._apply_default_build_testing_option()

        self.assertIn('-DBUILD_TESTING:BOOL=FALSE', list(product.cmake_options))

    def test_does_not_override_explicit_build_testing_setting(self):
        product = self.make_product(
            test_dummy=False,
            extra_cmake_options=['-DBUILD_TESTING:BOOL=TRUE'],
        )

        product._apply_default_build_testing_option()

        self.assertNotIn('-DBUILD_TESTING:BOOL=FALSE', list(product.cmake_options))

    def test_does_not_set_build_testing_when_product_tests_are_enabled(self):
        product = self.make_product(test_dummy=True)

        product._apply_default_build_testing_option()

        self.assertNotIn('-DBUILD_TESTING:BOOL=FALSE', list(product.cmake_options))
