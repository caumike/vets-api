# frozen_string_literal: true
class VHAFacilityAdapter
  VHA_URL = +ENV['VHA_MAPSERVER_URL']
  VHA_ID_FIELD = 'StationNumber'
  FACILITY_TYPE = 'va_health_facility'

  def initialize
    @client = Facilities::Client.new(url: VHA_URL, id_field: VHA_ID_FIELD)
  end

  def query(bbox, services = nil)
    @client.query(bbox: bbox.join(','),
                  where: self.class.where_clause(services))
  end

  def find_by(id:)
    @client.get(id: id)
  end

  def self.where_clause(services)
    services.map { |s| "#{s}='YES'" }.join(' AND ') unless services.nil?
  end

  def self.from_gis(record)
    attrs = record['attributes']
    m = from_gis_attrs(TOP_KEYMAP, attrs)
    m[:facility_type] = FACILITY_TYPE
    m[:address] = {}
    m[:address][:physical] = from_gis_attrs(ADDR_KEYMAP, attrs)
    m[:address][:physical][:zip] = attrs['Zip'].to_s
    m[:address][:physical][:zip] << '-' + attrs['Zip4'].to_s unless
      attrs['Zip4'].to_s.strip.empty?
    m[:address][:mailing] = {}
    m[:phone] = from_gis_attrs(PHONE_KEYMAP, attrs)
    m[:phone][:mental_health_clinic] = mh_clinic_phone(attrs)
    m[:hours] = from_gis_attrs(HOURS_KEYMAP, attrs)
    m[:services] = {}
    m[:services][:last_updated] = services_date(attrs)
    m[:services][:health] = services_from_gis(attrs)
    m[:feedback] = {}
    m[:feedback][:health] = from_gis_attrs(FEEDBACK_KEYMAP, attrs)
    VAFacility.new(m)
  end

  def service_whitelist
    SERVICE_HIERARCHY.flatten(2)
  end

  TOP_KEYMAP = {
    unique_id: 'StationNumber', name: 'StationName', classification: 'CocClassification',
    website: 'Website_URL', lat: 'Latitude', long: 'Longitude'
  }.freeze

  ADDR_KEYMAP = {
    'address_1' => 'Street', 'address_2' => 'Building', 'address_3' => 'Suite',
    'city' => 'City', 'state' => 'State'
  }.freeze

  PHONE_KEYMAP = {
    'main' => 'MainPhone', 'fax' => 'MainFax', 'after_hours' => 'AfterHoursPhone',
    'patient_advocate' => 'PatientAdvocatePhone',
    'enrollment_coordinator' => 'EnrollmentCoordinatorPhone',
    'pharmacy' => 'PharmacyPhone'
  }.freeze

  HOURS_KEYMAP = %w(
    Monday Tuesday Wednesday Thursday Friday Saturday Sunday
  ).each_with_object({}) { |d, h| h[d] = d }

  FEEDBACK_KEYMAP = {
    'primary_care_routine' => 'Primary_Care_Routine_Score',
    'primary_care_urgent' => 'Primary_Care_Urgent_Score',
    'specialty_care_routine' => 'Specialty_Care_Routine_Score',
    'specialty_care_urgent' => 'Specialty_Care_Urgent_Score'
  }.freeze

  SERVICE_HIERARCHY = {
    'Audiology' => [],
    'ComplementaryAlternativeMed' => [],
    'DentalServices' => [],
    'DiagnosticServices' => %w(
      ImagingAndRadiology LabServices
    ),
    'EmergencyDept' => [],
    'EyeCare' => [],
    'MentalHealthCare' => %w(
      OutpatientMHCare OutpatientSpecMHCare VocationalAssistance
    ),
    'OutpatientMedicalSpecialty' => %w(
      AllergyAndImmunology CardiologyCareServices DermatologyCareServices
      Diabetes Dialysis Endocrinology Gastroenterology
      Hematology InfectiousDisease InternalMedicine
      Nephrology Neurology Oncology
      PulmonaryRespiratoryDisease Rheumatology SleepMedicine
    ),
    'OutpatientSurgicalSpecialty' => %w(
      CardiacSurgery ColoRectalSurgery ENT GeneralSurgery
      Gynecology Neurosurgery Orthopedics PainManagement
      PlasticSurgery Podiatry ThoracicSurgery Urology
      VascularSurgery
    ),
    'PrimaryCare' => [],
    'Rehabilitation' => [],
    'UrgentCare' => [],
    'WellnessAndPreventativeCare' => []
  }.freeze

  # Filter services based on what has been organizationally approved for publication
  APPROVED_SERVICES = %w(
    MentalHealthCare
    PrimaryCare
    DentalServices
  ).freeze

  def self.mh_clinic_phone(attrs)
    return '' if (attrs['MHClinicPhone']).blank?
    result = attrs['MHClinicPhone'].to_s
    result << ' x ' + attrs['Extension'].to_s unless
      (attrs['Extension']).blank? || (attrs['Extension']).zero?
    result
  end

  def self.services_date(attrs)
    Time.at(attrs['OutpatientServicesDataDate'] / 1000).utc.to_date.iso8601 if attrs['OutpatientServicesDataDate']
  end

  # Build a sub-section of the VAFacility model from a flat GIS attribute list,
  # according to the provided key mapping dict. Strip whitespace from string values.
  def self.from_gis_attrs(km, attrs)
    km.each_with_object({}) do |(k, v), h|
      h[k] = (attrs[v].respond_to?(:strip) ? attrs[v].strip : attrs[v])
    end
  end

  # Construct the services hierarchy from a flat GIS attribute list.
  # The hierarchy of Level 1/Level 2 services is defined statically above.
  # Return a list of dicts each containing key 'sl1' => Level 1 service and
  # 'sl2' => list of Level 2 services
  def self.services_from_gis(attrs)
    SERVICE_HIERARCHY.each_with_object([]) do |(k, v), l|
      next unless attrs[k] == 'YES' && APPROVED_SERVICES.include?(k)
      sl2 = []
      v.each do |sk|
        sl2 << sk if attrs[sk] == 'YES' && APPROVED_SERVICES.include?(sk)
      end
      l << { 'sl1' => [k], 'sl2' => sl2 }
    end
  end
end
