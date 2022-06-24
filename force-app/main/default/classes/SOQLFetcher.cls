/**
 * @description: Extracts and parses the information from SOQL. 
**/
public with sharing class SOQLFetcher extends MetadataFetcher{
    
    private final string SOQL ='SOQL';
    private static final string FLOWS = 'Flow';
    private static final string PROCESS_BUILDER = 'Workflow';
    @TestVisible private List<SObject> metadataObjects = new List<SObject>();

    /**
    * @description Query each object dinamically for each supported type
    * @param sobjectNames 
    * @param categories 
    * @return Map<String, List<CategoryOperation>> 
    **/
    public override Map<String, List<CategoryOperation>> requestMetadata(List<String> sobjectNames, Set<String> categories) {
        init(sobjectNames, categories);
        // Need to do 3 different queries depending the object passed
        // For each object, launch a query.
        String objectDesc = '%'+String.join(sobjectNames, ',')+'%';
        for(CategorySetting__mdt category : CategorySettingHelper.getCategorySettingsByOperation(SOQL)){
            try {
                String query = 'SELECT ' + category.Fields__c+ ' FROM ' + category.ApiName__c + ' WHERE SobjectType IN :sobjectNames';
                if (FLOWS.equalsIgnoreCase(category.ApiName__c)){
                    query = 'SELECT ' + category.Fields__c+ ' FROM FlowDefinitionView WHERE isActive = True AND '+category.FieldFilter__c;
                    if (category.Label != 'Process Builders')
                    	query+=' in :sobjectNames';
                    else
                    	query+= ' like :objectDesc AND ProcessType = :PROCESS_BUILDER';                        
                }
                metadataObjects.addAll(Database.query(String.escapeSingleQuotes(query)));
            } catch(QueryException e) {
                //Ignore exception when Object is not present in the organization
                if(e.getMessage().startsWith(String.format(System.Label.QUERY_OBJECT_EXCEPTION, new List<String> {category.ApiName__c}))) {
                    System.debug(e.getMessage());
                } else {
                    throw e;
                }
            }
            
        }

        parseMetadata();

        return this.operationsByObject;
    }

    /**
    * @description Parse each of the entities into a CategoryOperation and stores to the corresponding object
    **/
    protected override void parseMetadata() {
        List<CategoryOperation> categoryOperations = new List<CategoryOperation>();
		Set<String> flowsUnique = new Set<String>();
        for(SObject metadataObject : metadataObjects) {
            //For each SObject need to know which mapping apply
            String objectName = metadataObject.getSObjectType().getDescribe().getName();
            if (objectName != 'FlowDefinitionView'){
            	Type t = Type.forName('OperationMapping.' + objectName);
                OperationMapping opMapping = (OperationMapping)t.newInstance();
                if ((Boolean)getFieldValue(metadataObject, opMapping.active)){
                    CategoryOperation.Operation newOperation = new CategoryOperation.Operation();
                    newOperation.label = (String)getFieldValue(metadataObject, opMapping.label);
                    newOperation.developerName = (String)getFieldValue(metadataObject, opMapping.developerName);
                    newOperation.namespace = (String)getFieldValue(metadataObject, opMapping.namespace);
                    newOperation.createdDate = (Datetime)(getFieldValue(metadataObject, opMapping.createdDate));
                    newOperation.lastModifiedDate = (Datetime)(getFieldValue(metadataObject, opMapping.lastModifiedDate));
                    Integer indexCategory = this.getCategoryIndex(CategorySettingHelper.getCategorySettingByName(objectName).label);
                    //Each record needs to be added to the map with the corresponding SObjectType that it belongs to
                    this.operationsByObject.get((String)metadataObject.get('SobjectType'))[indexCategory].operations.add(newOperation);
                }                
            } else {
                String processType = (String)getFieldValue(metadataObject, 'ProcessType'  );
                if (processType != 'Workflow'){
                    String triggerType = (String)getFieldValue(metadataObject, 'TriggerType'  );
                    CategoryOperation.Operation newOperation = new CategoryOperation.Operation();
                    newOperation.label = (String)getFieldValue(metadataObject, 'Label');
                    newOperation.developerName = (String)getFieldValue(metadataObject, 'ApiName');
                    newOperation.lastModifiedDate = (Datetime)(getFieldValue(metadataObject, 'LastModifiedDate'  ))  ;
                    Integer indexCategory = this.getCategoryIndex(CategorySettingHelper.getCategorySettingByName(triggerType).label);
                    //Each record needs to be added to the map with the corresponding SObjectType that it belongs to
                    if (!flowsUnique.contains(triggerType + newOperation.label)){
                    	this.operationsByObject.get(this.sobjectNames[0])[indexCategory].operations.add(newOperation);                    
                        flowsUnique.add(triggerType+newOperation.label);
                    }
                } else {
					CategoryOperation.Operation newOperation = new CategoryOperation.Operation();
                    newOperation.label = (String)getFieldValue(metadataObject, 'Label');
                    newOperation.developerName = (String)getFieldValue(metadataObject, 'ApiName');
                    newOperation.lastModifiedDate = (Datetime)(getFieldValue(metadataObject, 'LastModifiedDate'  ))  ;
                    Integer indexCategory = this.getCategoryIndex(CategorySettingHelper.getCategorySettingByName('ProcessBuilder').label);
                    //Each record needs to be added to the map with the corresponding SObjectType that it belongs to
                    if (!flowsUnique.contains(processType + newOperation.label)){
                    	this.operationsByObject.get(this.sobjectNames[0])[indexCategory].operations.add(newOperation);                    
                        flowsUnique.add(processType+newOperation.label);                    
                	}
            	}	   
    }
        }}
    /**
    * @description Get field value regardless of type
    * @param metadataObject 
    * @param fieldName 
    * @return Object 
    **/
    private Object getFieldValue(SObject metadataObject, String fieldName) {
        Object fieldValue = fieldName != null ? metadataObject.get(fieldName) : null;
        return fieldValue;
    }
}