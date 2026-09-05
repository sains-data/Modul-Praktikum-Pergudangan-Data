{#
  Macro: kolom_audit
  ------------------
  Menambahkan kolom metadata pemuatan yang sama pada setiap model mart.

  Ditulis sekali sebagai macro, bukan disalin ke setiap model, supaya
  perubahan definisi metadata cukup dilakukan di satu tempat.

  Pemakaian di dalam model:

      SELECT ...,
             {{ kolom_audit() }}
      FROM   ...
#}
{% macro kolom_audit() %}
    CURRENT_TIMESTAMP           AS dibangun_pada,
    '{{ invocation_id }}'       AS dbt_invocation_id,
    '{{ this.name }}'           AS dibangun_oleh_model
{% endmacro %}
