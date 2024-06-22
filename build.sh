odin build . \
	-out:odin-deps \
	-o:aggressive \
	-error-pos-style:unix \
	-microarch:native \
	-no-type-assert \
	-no-bounds-check \
	-disable-assert