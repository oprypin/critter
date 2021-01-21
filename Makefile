release ?=

critter: $(wildcard *.cr) lib lib/markdown
	shards build --error-trace $(if $(release),--release )critter

lib: shard.lock
	shards install

lib/markdown: crystal.zip
	unzip -o crystal.zip 'crystal-b3feebdef9b8cc67834207b8fdcd65ff04394ec1/src/markdown*'
	mkdir -p lib
	mv crystal-b3feebdef9b8cc67834207b8fdcd65ff04394ec1/src/* lib/

crystal.zip:
	curl -L -o $@ https://github.com/crystal-lang/crystal/archive/b3feebdef9b8cc67834207b8fdcd65ff04394ec1.zip

shard.lock: shard.yml
	shards update

.PHONY: clean
clean:
	rm -f bin/critter
