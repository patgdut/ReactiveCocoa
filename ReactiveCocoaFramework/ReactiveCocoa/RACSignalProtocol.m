//
//  RACSignalProtocol.m
//  ReactiveCocoa
//
//  Created by Justin Spahr-Summers on 2012-09-06.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACSignalProtocol.h"
#import "NSObject+RACExtensions.h"
#import "RACBehaviorSubject.h"
#import "RACCancelableSignal+Private.h"
#import "RACConnectableSignal+Private.h"
#import "RACDisposable.h"
#import "RACGroupedSignal.h"
#import "RACMaybe.h"
#import "RACScheduler.h"
#import "RACSubject.h"
#import "RACSignalSequence.h"
#import "RACSubscriber.h"
#import "RACTuple.h"
#import "RACUnit.h"
#import <libkern/OSAtomic.h>
#import "NSObject+RACPropertySubscribing.h"
#import "RACBlockTrampoline.h"
#import "NSObject+RACFastEnumeration.h"

NSString * const RACSignalErrorDomain = @"RACSignalErrorDomain";

@concreteprotocol(RACSignal)

#pragma mark RACStream

+ (instancetype)empty {
	return nil;
}

+ (instancetype)return:(id)value {
	return nil;
}

// We can't actually provide a useful default implementation of these methods,
// because conforming classes will be required to implement them anyways.
- (instancetype)bind:(id (^)(id value))block {
	return nil;
}

- (instancetype)concat:(id<RACStream>)stream {
	return nil;
}

- (instancetype)flatten {
	return nil;
}

+ (instancetype)zip:(NSArray *)streams reduce:(id)reduceBlock {
	return nil;
}

#pragma mark RACSignal

- (RACDisposable *)subscribe:(id<RACSubscriber>)subscriber {
	return nil;
}

- (RACDisposable *)subscribeNext:(void (^)(id x))nextBlock {
	NSParameterAssert(nextBlock != NULL);
	
	RACSubscriber *o = [RACSubscriber subscriberWithNext:nextBlock error:NULL completed:NULL];
	return [self subscribe:o];
}

- (RACDisposable *)subscribeNext:(void (^)(id x))nextBlock completed:(void (^)(void))completedBlock {
	NSParameterAssert(nextBlock != NULL);
	NSParameterAssert(completedBlock != NULL);
	
	RACSubscriber *o = [RACSubscriber subscriberWithNext:nextBlock error:NULL completed:completedBlock];
	return [self subscribe:o];
}

- (RACDisposable *)subscribeNext:(void (^)(id x))nextBlock error:(void (^)(NSError *error))errorBlock completed:(void (^)(void))completedBlock {
	NSParameterAssert(nextBlock != NULL);
	NSParameterAssert(errorBlock != NULL);
	NSParameterAssert(completedBlock != NULL);
	
	RACSubscriber *o = [RACSubscriber subscriberWithNext:nextBlock error:errorBlock completed:completedBlock];
	return [self subscribe:o];
}

- (RACDisposable *)subscribeError:(void (^)(NSError *error))errorBlock {
	NSParameterAssert(errorBlock != NULL);
	
	RACSubscriber *o = [RACSubscriber subscriberWithNext:NULL error:errorBlock completed:NULL];
	return [self subscribe:o];
}

- (RACDisposable *)subscribeCompleted:(void (^)(void))completedBlock {
	NSParameterAssert(completedBlock != NULL);
	
	RACSubscriber *o = [RACSubscriber subscriberWithNext:NULL error:NULL completed:completedBlock];
	return [self subscribe:o];
}

- (RACDisposable *)subscribeNext:(void (^)(id x))nextBlock error:(void (^)(NSError *error))errorBlock {
	NSParameterAssert(nextBlock != NULL);
	NSParameterAssert(errorBlock != NULL);
	
	RACSubscriber *o = [RACSubscriber subscriberWithNext:nextBlock error:errorBlock completed:NULL];
	return [self subscribe:o];
}

- (RACDisposable *)subscribeError:(void (^)(NSError *))errorBlock completed:(void (^)(void))completedBlock {
	NSParameterAssert(completedBlock != NULL);
	NSParameterAssert(errorBlock != NULL);
	
	RACSubscriber *o = [RACSubscriber subscriberWithNext:NULL error:errorBlock completed:completedBlock];
	return [self subscribe:o];
}

- (id<RACSignal>)mapReplace:(id)object {
	return [self map:^(id _) {
		return object;
	}];
}

- (id<RACSignal>)injectObjectWeakly:(id)object {
	__unsafe_unretained id weakObject = object;
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		return [self subscribeNext:^(id x) {
			id strongObject = weakObject;
			[subscriber sendNext:[RACTuple tupleWithObjectsFromArray:[NSArray arrayWithObjects:x ? : [RACTupleNil tupleNil], strongObject, nil]]];
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			[subscriber sendCompleted];
		}];
	}];
}

- (id<RACSignal>)doNext:(void (^)(id x))block {
	NSParameterAssert(block != NULL);

	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		return [self subscribeNext:^(id x) {
			block(x);
			[subscriber sendNext:x];
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			[subscriber sendCompleted];
		}];
	}];
}

- (id<RACSignal>)doError:(void (^)(NSError *error))block {
	NSParameterAssert(block != NULL);
	
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		return [self subscribeNext:^(id x) {
			[subscriber sendNext:x];
		} error:^(NSError *error) {
			block(error);
			[subscriber sendError:error];
		} completed:^{
			[subscriber sendCompleted];
		}];
	}];
}

- (id<RACSignal>)doCompleted:(void (^)(void))block {
	NSParameterAssert(block != NULL);
	
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		return [self subscribeNext:^(id x) {
			[subscriber sendNext:x];
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			block();
			[subscriber sendCompleted];
		}];
	}];
}

- (id<RACSignal>)throttle:(NSTimeInterval)interval {
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		__block id lastDelayedId = nil;
		return [self subscribeNext:^(id x) {
			if(lastDelayedId != nil) [self rac_cancelPreviousPerformBlockRequestsWithId:lastDelayedId];
			lastDelayedId = [self rac_performBlock:^{
				[subscriber sendNext:x];
			} afterDelay:interval];
		} error:^(NSError *error) {
			[self rac_cancelPreviousPerformBlockRequestsWithId:lastDelayedId];
			[subscriber sendError:error];
		} completed:^{
			[subscriber sendCompleted];
		}];
	}];
}

- (id<RACSignal>)delay:(NSTimeInterval)interval {
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		__block id lastDelayedId = nil;
		return [self subscribeNext:^(id x) {
			lastDelayedId = [self rac_performBlock:^{
				[subscriber sendNext:x];
			} afterDelay:interval];
		} error:^(NSError *error) {
			[self rac_cancelPreviousPerformBlockRequestsWithId:lastDelayedId];
			[subscriber sendError:error];
		} completed:^{
			[subscriber sendCompleted];
		}];
	}];
}

- (id<RACSignal>)repeat {
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		__block RACDisposable *currentDisposable = nil;
		
		__block RACSubscriber *innerObserver = [RACSubscriber subscriberWithNext:^(id x) {
			[subscriber sendNext:x];
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			currentDisposable = [self subscribe:innerObserver];
		}];
		
		currentDisposable = [self subscribe:innerObserver];
		
		return [RACDisposable disposableWithBlock:^{
			[currentDisposable dispose];
		}];
	}];
}

- (id<RACSignal>)asMaybes {
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		__block RACDisposable *currentDisposable = nil;
		
		__block RACSubscriber *innerObserver = [RACSubscriber subscriberWithNext:^(id x) {
			[subscriber sendNext:[RACMaybe maybeWithObject:x]];
		} error:^(NSError *error) {
			[subscriber sendNext:[RACMaybe maybeWithError:error]];
			currentDisposable = [self subscribe:innerObserver];
		} completed:^{
			[subscriber sendCompleted];
		}];
		
		currentDisposable = [self subscribe:innerObserver];
		
		return [RACDisposable disposableWithBlock:^{
			[currentDisposable dispose];
		}];
	}];
}

- (id<RACSignal>)catch:(id<RACSignal> (^)(NSError *error))catchBlock {
	NSParameterAssert(catchBlock != NULL);
		
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		__block RACDisposable *innerDisposable = nil;
		RACDisposable *outerDisposable = [self subscribeNext:^(id x) {
			[subscriber sendNext:x];
		} error:^(NSError *error) {
			id<RACSignal> signal = catchBlock(error);
			innerDisposable = [signal subscribe:[RACSubscriber subscriberWithNext:^(id x) {
				[subscriber sendNext:x];
			} error:^(NSError *error) {
				[subscriber sendError:error];
			} completed:^{
				[subscriber sendCompleted];
			}]];
		} completed:^{
			[subscriber sendCompleted];
		}];
		
		return [RACDisposable disposableWithBlock:^{
			[innerDisposable dispose];
			[outerDisposable dispose];
		}];
	}];
}

- (id<RACSignal>)catchTo:(id<RACSignal>)signal {
	return [self catch:^(NSError *error) {
		return signal;
	}];
}

- (id<RACSignal>)finally:(void (^)(void))block {
	NSParameterAssert(block != NULL);
	
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		return [self subscribeNext:^(id x) {
			[subscriber sendNext:x];
		} error:^(NSError *error) {
			[subscriber sendError:error];
			block();
		} completed:^{
			[subscriber sendCompleted];
			block();
		}];
	}];
}

- (id<RACSignal>)windowWithStart:(id<RACSignal>)openSignal close:(id<RACSignal> (^)(id<RACSignal> start))closeBlock {
	NSParameterAssert(openSignal != nil);
	NSParameterAssert(closeBlock != NULL);
	
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		__block RACSubject *currentWindow = nil;
		__block id<RACSignal> currentCloseWindow = nil;
		__block RACDisposable *closeObserverDisposable = NULL;
		
		void (^closeCurrentWindow)(void) = ^{
			[currentWindow sendCompleted];
			currentWindow = nil;
			currentCloseWindow = nil;
			[closeObserverDisposable dispose], closeObserverDisposable = nil;
		};
		
		RACDisposable *openObserverDisposable = [openSignal subscribe:[RACSubscriber subscriberWithNext:^(id x) {
			if(currentWindow == nil) {
				currentWindow = [RACSubject subject];
				[subscriber sendNext:currentWindow];
				
				currentCloseWindow = closeBlock(currentWindow);
				closeObserverDisposable = [currentCloseWindow subscribe:[RACSubscriber subscriberWithNext:^(id x) {
					closeCurrentWindow();
				} error:^(NSError *error) {
					closeCurrentWindow();
				} completed:^{
					closeCurrentWindow();
				}]];
			}
		} error:^(NSError *error) {
			
		} completed:^{
			
		}]];
				
		RACDisposable *selfObserverDisposable = [self subscribeNext:^(id x) {
			[currentWindow sendNext:x];
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			[subscriber sendCompleted];
		}];
				
		return [RACDisposable disposableWithBlock:^{
			[closeObserverDisposable dispose];
			[openObserverDisposable dispose];
			[selfObserverDisposable dispose];
		}];
	}];
}

- (id<RACSignal>)buffer:(NSUInteger)bufferCount {
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		NSMutableArray *values = [NSMutableArray arrayWithCapacity:bufferCount];
		RACBehaviorSubject *windowOpenSubject = [RACBehaviorSubject behaviorSubjectWithDefaultValue:[RACUnit defaultUnit]];
		RACSubject *windowCloseSubject = [RACSubject subject];
		
		__block RACDisposable *innerDisposable = nil;
		RACDisposable *outerDisposable = [[self windowWithStart:windowOpenSubject close:^(id<RACSignal> start) {
			return windowCloseSubject;
		}] subscribeNext:^(id x) {		
			innerDisposable = [x subscribeNext:^(id x) {
				if(values.count % bufferCount == 0) {
					[subscriber sendNext:x];
					[windowCloseSubject sendNext:[RACUnit defaultUnit]];
					[windowOpenSubject sendNext:[RACUnit defaultUnit]];
				}
			}];
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			[subscriber sendCompleted];
		}];

		return [RACDisposable disposableWithBlock:^{
			[innerDisposable dispose];
			[outerDisposable dispose];
		}];
	}];
}

- (id<RACSignal>)bufferWithTime:(NSTimeInterval)interval {
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		NSMutableArray *values = [NSMutableArray array];
		RACBehaviorSubject *windowOpenSubject = [RACBehaviorSubject behaviorSubjectWithDefaultValue:[RACUnit defaultUnit]];

		__block RACDisposable *innerDisposable = nil;
		RACDisposable *outerDisposable = [[self windowWithStart:windowOpenSubject close:^(id<RACSignal> start) {
			return [[[RACSignal interval:interval] take:1] doNext:^(id x) {
				[subscriber sendNext:[RACTuple tupleWithObjectsFromArray:values convertNullsToNils:YES]];
				[values removeAllObjects];
				[windowOpenSubject sendNext:[RACUnit defaultUnit]];
			}];
		}] subscribeNext:^(id x) {
			innerDisposable = [x subscribeNext:^(id x) {
				[values addObject:x ? : [RACTupleNil tupleNil]];
			}];
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			[subscriber sendCompleted];
		}];

		return [RACDisposable disposableWithBlock:^{
			[innerDisposable dispose];
			[outerDisposable dispose];
		}];
	}];
}

- (id<RACSignal>)takeLast:(NSUInteger)count {
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {		
		NSMutableArray *valuesTaken = [NSMutableArray arrayWithCapacity:count];
		return [self subscribeNext:^(id x) {
			[valuesTaken addObject:x ? : [RACTupleNil tupleNil]];
			
			while(valuesTaken.count > count) {
				[valuesTaken removeObjectAtIndex:0];
			}
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			for(id value in valuesTaken) {
				[subscriber sendNext:[value isKindOfClass:[RACTupleNil class]] ? nil : value];
			}
			
			[subscriber sendCompleted];
		}];
	}];
}

+ (id<RACSignal>)combineLatest:(NSArray *)signals reduce:(id)reduceBlock {
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		NSMutableSet *disposables = [NSMutableSet setWithCapacity:signals.count];
		NSMutableSet *completedSignals = [NSMutableSet setWithCapacity:signals.count];
		NSMutableDictionary *lastValues = [NSMutableDictionary dictionaryWithCapacity:signals.count];
		for(id<RACSignal> signal in signals) {
			RACDisposable *disposable = [signal subscribe:[RACSubscriber subscriberWithNext:^(id x) {
				@synchronized(lastValues) {
					[lastValues setObject:x ? : [RACTupleNil tupleNil] forKey:[NSString stringWithFormat:@"%p", signal]];

					if(lastValues.count == signals.count) {
						NSMutableArray *orderedValues = [NSMutableArray arrayWithCapacity:signals.count];
						for(id<RACSignal> o in signals) {
							[orderedValues addObject:[lastValues objectForKey:[NSString stringWithFormat:@"%p", o]]];
						}

						if (reduceBlock == NULL) {
							[subscriber sendNext:[RACTuple tupleWithObjectsFromArray:orderedValues]];
						} else {
							[subscriber sendNext:[RACBlockTrampoline invokeBlock:reduceBlock withArguments:orderedValues]];
						}
					}
				}
			} error:^(NSError *error) {
				[subscriber sendError:error];
			} completed:^{
				@synchronized(completedSignals) {
					[completedSignals addObject:signal];
					if(completedSignals.count == signals.count) {
						[subscriber sendCompleted];
					}
				}
			}]];

			if(disposable != nil) {
				[disposables addObject:disposable];
			}
		}

		return [RACDisposable disposableWithBlock:^{
			for(RACDisposable *disposable in disposables) {
				[disposable dispose];
			}
		}];
	}];
}

+ (id<RACSignal>)combineLatest:(NSArray *)signals {
	return [self combineLatest:signals reduce:nil];
}

+ (id<RACSignal>)merge:(NSArray *)signals {
	return [signals.rac_toSignal flatten];
}

- (id<RACSignal>)flatten:(NSUInteger)maxConcurrent {
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		NSMutableSet *activeSignals = [NSMutableSet setWithObject:self];
		NSMutableSet *disposables = [NSMutableSet set];
		NSMutableArray *queuedSignals = [NSMutableArray array];

		// Returns whether the signal should complete.
		__block BOOL (^dequeueAndSubscribeIfAllowed)(void);
		void (^completeSignal)(id<RACSignal>) = ^(id<RACSignal> signal) {
			@synchronized(activeSignals) {
				[activeSignals removeObject:signal];
			}
			
			BOOL completed = dequeueAndSubscribeIfAllowed();
			if (completed) {
				[subscriber sendCompleted];
			}
		};

		void (^addDisposable)(RACDisposable *) = ^(RACDisposable *disposable) {
			if (disposable == nil) return;
			
			@synchronized(disposables) {
				[disposables addObject:disposable];
			}
		};

		dequeueAndSubscribeIfAllowed = ^{
			id<RACSignal> signal;
			@synchronized(activeSignals) {
				@synchronized(queuedSignals) {
					BOOL completed = activeSignals.count < 1 && queuedSignals.count < 1;
					if (completed) return YES;

					// We add one to maxConcurrent since self is an active
					// signal at the start and we don't want that to count
					// against the max.
					NSUInteger maxIncludingSelf = maxConcurrent + ([activeSignals containsObject:self] ? 1 : 0);
					if (activeSignals.count >= maxIncludingSelf && maxConcurrent != 0) return NO;

					if (queuedSignals.count < 1) return NO;

					signal = queuedSignals[0];
					[queuedSignals removeObjectAtIndex:0];

					[activeSignals addObject:signal];
				}
			}

			RACDisposable *disposable = [signal subscribe:[RACSubscriber subscriberWithNext:^(id x) {
				[subscriber sendNext:x];
			} error:^(NSError *error) {
				[subscriber sendError:error];
			} completed:^{
				completeSignal(signal);
			}]];

			addDisposable(disposable);

			return NO;
		};

		RACDisposable *disposable = [self subscribeNext:^(id x) {
			NSAssert([x conformsToProtocol:@protocol(RACSignal)], @"The source must be a signal of signals. Instead, got %@", x);

			id<RACSignal> innerSignal = x;
			@synchronized(queuedSignals) {
				[queuedSignals addObject:innerSignal];
			}

			dequeueAndSubscribeIfAllowed();
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			completeSignal(self);
		}];

		addDisposable(disposable);

		return [RACDisposable disposableWithBlock:^{
			@synchronized(disposables) {
				[disposables makeObjectsPerformSelector:@selector(dispose)];
			}
		}];
	}];
}

- (id<RACSignal>)sequenceNext:(id<RACSignal> (^)(void))block {
	NSParameterAssert(block != nil);

	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		__block RACDisposable *nextDisposable = nil;

		RACDisposable *sourceDisposable = [self subscribeError:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			nextDisposable = [block() subscribe:subscriber];
		}];
		
		return [RACDisposable disposableWithBlock:^{
			[sourceDisposable dispose];
			[nextDisposable dispose];
		}];
	}];
}

- (id<RACSignal>)concat {
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		__block NSMutableArray *innerSignals = [NSMutableArray array];
		__block RACDisposable *currentDisposable = nil;
		__block BOOL outerDone = NO;
		__block RACSubscriber *innerSubscriber = nil;
		
		void (^startNextInnerSignal)(void) = ^{
			if(innerSignals.count < 1) return;
			
			id<RACSignal> currentInnerSignal = [innerSignals objectAtIndex:0];
			[innerSignals removeObjectAtIndex:0];
			currentDisposable = [currentInnerSignal subscribe:innerSubscriber];
		};
		
		void (^sendCompletedIfWeReallyAreDone)(void) = ^{
			if(outerDone && innerSignals.count < 1 && currentDisposable == nil) {
				[subscriber sendCompleted];
			}
		};
		
		innerSubscriber = [RACSubscriber subscriberWithNext:^(id x) {
			[subscriber sendNext:x];
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			currentDisposable = nil;
			
			startNextInnerSignal();
			sendCompletedIfWeReallyAreDone();
		}];
		
		RACDisposable *sourceDisposable = [self subscribeNext:^(id x) {
			NSAssert1([x conformsToProtocol:@protocol(RACSignal)], @"The source must be a signal of signals. Instead, got %@", x);
			[innerSignals addObject:x];
			
			if(currentDisposable == nil) {
				startNextInnerSignal();
			}
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			outerDone = YES;
			
			sendCompletedIfWeReallyAreDone();
		}];
		
		return [RACDisposable disposableWithBlock:^{
			innerSignals = nil;
			[sourceDisposable dispose];
			[currentDisposable dispose];
		}];
	}];
}

- (id<RACSignal>)aggregateWithStartFactory:(id (^)(void))startFactory combine:(id (^)(id running, id next))combineBlock {
	NSParameterAssert(startFactory != NULL);
	NSParameterAssert(combineBlock != NULL);
	
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		__block id runningValue = startFactory();
		return [self subscribeNext:^(id x) {
			runningValue = combineBlock(runningValue, x);
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			[subscriber sendNext:runningValue];
			[subscriber sendCompleted];
		}];
	}];
}

- (id<RACSignal>)scanWithStart:(id)start combine:(id (^)(id running, id next))combineBlock {
	NSParameterAssert(combineBlock != NULL);

	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		__block id runningValue = start;

		return [self subscribeNext:^(id x) {
			runningValue = combineBlock(runningValue, x);
			[subscriber sendNext:runningValue];
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			[subscriber sendCompleted];
		}];
	}];
}

- (id<RACSignal>)aggregateWithStart:(id)start combine:(id (^)(id running, id next))combineBlock {
	return [self aggregateWithStartFactory:^{
		return start;
	} combine:combineBlock];
}

- (RACDisposable *)toProperty:(NSString *)keyPath onObject:(NSObject *)object {
	NSParameterAssert(keyPath != nil);
	NSParameterAssert(object != nil);
	
	__block __unsafe_unretained NSObject *weakObject = object;
	RACDisposable *subscriptionDisposable = [self subscribeNext:^(id x) {
		NSObject *strongObject = weakObject;
		[strongObject setValue:x forKeyPath:keyPath];
	}];
	
	RACDisposable *disposable = [RACDisposable disposableWithBlock:^{
		weakObject = nil;
		[subscriptionDisposable dispose];
	}];

	[object rac_addDeallocDisposable:disposable];

	return disposable;
}

+ (id<RACSignal>)interval:(NSTimeInterval)interval {
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		NSTimer *timer = [NSTimer timerWithTimeInterval:interval target:self selector:@selector(intervalTimerFired:) userInfo:subscriber repeats:YES];
		CFRunLoopAddTimer(CFRunLoopGetMain(), (__bridge CFRunLoopTimerRef)timer, kCFRunLoopCommonModes);

		return [RACDisposable disposableWithBlock:^{
			[timer invalidate];
		}];
	}];
}

+ (void)intervalTimerFired:(NSTimer *)timer {
	RACSubscriber *subscriber = timer.userInfo;
	[subscriber sendNext:NSDate.date];
}

- (id<RACSignal>)takeUntil:(id<RACSignal>)signalTrigger {
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		__block RACDisposable *selfDisposable = nil;
		__block RACDisposable *triggerDisposable = [signalTrigger subscribe:[RACSubscriber subscriberWithNext:^(id x) {
			[selfDisposable dispose], selfDisposable = nil;
			[subscriber sendCompleted];
		} error:^(NSError *error) {
			
		} completed:^{
			
		}]];
		
		selfDisposable = [self subscribeNext:^(id x) {
			[subscriber sendNext:x];
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			[triggerDisposable dispose];
			[subscriber sendCompleted];
		}];
		
		return [RACDisposable disposableWithBlock:^{
			[triggerDisposable dispose];
			[selfDisposable dispose];
		}];
	}];
}

- (id<RACSignal>)takeUntilBlock:(BOOL (^)(id x))predicate {
	NSParameterAssert(predicate != NULL);
	
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		__block RACDisposable *selfDisposable = [self subscribeNext:^(id x) {
			BOOL stop = predicate(x);
			if(stop) {
				[selfDisposable dispose], selfDisposable = nil;
				[subscriber sendCompleted];
				return;
			}
			
			[subscriber sendNext:x];
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			[subscriber sendCompleted];
		}];
		
		return [RACDisposable disposableWithBlock:^{
			[selfDisposable dispose];
		}];
	}];
}

- (id<RACSignal>)takeWhileBlock:(BOOL (^)(id x))predicate {
	NSParameterAssert(predicate != NULL);
	
	return [self takeUntilBlock:^BOOL(id x) {
		return !predicate(x);
	}];
}

- (id<RACSignal>)switch {
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		__block RACDisposable *innerDisposable = nil;
		RACDisposable *selfDisposable = [self subscribeNext:^(id x) {
			NSAssert([x conformsToProtocol:@protocol(RACSignal)] || x == nil, @"-switch requires that the source signal (%@) send signals. Instead we got: %@", self, x);
			
			[innerDisposable dispose], innerDisposable = nil;
			
			innerDisposable = [x subscribeNext:^(id x) {
				[subscriber sendNext:x];
			} error:^(NSError *error) {
				[subscriber sendError:error];
			}];
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			[subscriber sendCompleted];
		}];
		
		return [RACDisposable disposableWithBlock:^{
			[innerDisposable dispose];
			[selfDisposable dispose];
		}];
	}];
}

- (id)first {
	return [self firstOrDefault:nil];
}

- (id)firstOrDefault:(id)defaultValue {
	return [self firstOrDefault:defaultValue success:NULL error:NULL];
}

- (id)firstOrDefault:(id)defaultValue success:(BOOL *)success error:(NSError **)error {
	NSCondition *condition = [[NSCondition alloc] init];
	condition.name = NSStringFromSelector(_cmd);

	__block id value = defaultValue;

	// Protects against setting 'value' multiple times (e.g. to the second value
	// instead of the first).
	__block BOOL done = NO;

	__block RACDisposable *disposable = [self subscribeNext:^(id x) {
		[condition lock];

		if (!done) {
			value = x;
			if(success != NULL) *success = YES;
			
			done = YES;
			[disposable dispose];
			[condition broadcast];
		}

		[condition unlock];
	} error:^(NSError *e) {
		[condition lock];

		if(success != NULL) *success = NO;
		if(error != NULL) *error = e;

		done = YES;
		[condition broadcast];
		[condition unlock];
	} completed:^{
		[condition lock];

		if(success != NULL) *success = YES;

		done = YES;
		[condition broadcast];
		[condition unlock];
	}];

	[condition lock];
	while (!done) {
		[condition wait];
	}

	[condition unlock];
	return value;
}

+ (id<RACSignal>)defer:(id<RACSignal> (^)(void))block {
	NSParameterAssert(block != NULL);
	
	return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
		id<RACSignal> signal = block();
		return [signal subscribe:[RACSubscriber subscriberWithNext:^(id x) {
			[subscriber sendNext:x];
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			[subscriber sendCompleted];
		}]];
	}];
}

- (id<RACSignal>)skipUntilBlock:(BOOL (^)(id x))block {
	NSParameterAssert(block != NULL);
	
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		__block BOOL keepSkipping = YES;
		return [self subscribeNext:^(id x) {
			if(keepSkipping) {
				keepSkipping = !block(x);
			}
			
			if(!keepSkipping) {
				[subscriber sendNext:x];
			}
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			[subscriber sendCompleted];
		}];
	}];
}

- (id<RACSignal>)skipWhileBlock:(BOOL (^)(id x))block {
	NSParameterAssert(block != NULL);
	
	return [self skipUntilBlock:^BOOL(id x) {
		return !block(x);
	}];
}

- (id<RACSignal>)distinctUntilChanged {
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		__block id lastValue = nil;
		__block BOOL initial = YES;

		return [self subscribeNext:^(id x) {
			if (initial || (lastValue != x && ![x isEqual:lastValue])) {
				initial = NO;
				lastValue = x;
				[subscriber sendNext:x];
			}
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			[subscriber sendCompleted];
		}];
	}];
}

- (NSArray *)toArray {
	NSCondition *condition = [[NSCondition alloc] init];
	condition.name = @(__func__);

	NSMutableArray *values = [NSMutableArray array];
	__block BOOL done = NO;
	[self subscribeNext:^(id x) {
		[values addObject:x ? : [NSNull null]];
	} error:^(NSError *error) {
		[condition lock];
		done = YES;
		[condition broadcast];
		[condition unlock];
	} completed:^{
		[condition lock];
		done = YES;
		[condition broadcast];
		[condition unlock];
	}];

	[condition lock];
	while (!done) {
		[condition wait];
	}

	[condition unlock];

	return [values copy];
}

- (RACSequence *)sequence {
	return [RACSignalSequence sequenceWithSignal:self];
}

- (RACConnectableSignal *)publish {
	return [self multicast:[RACSubject subject]];
}

- (RACConnectableSignal *)multicast:(RACSubject *)subject {
	return [RACConnectableSignal connectableSignalWithSourceSignal:self subject:subject];
}

- (id<RACSignal>)timeout:(NSTimeInterval)interval {
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		__block volatile uint32_t cancelTimeout = 0;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (interval * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			if(cancelTimeout) return;
			
			[subscriber sendError:[NSError errorWithDomain:RACSignalErrorDomain code:RACSignalErrorTimedOut userInfo:nil]];
		});
		
		RACDisposable *disposable = [self subscribeNext:^(id x) {
			[subscriber sendNext:x];
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			OSAtomicOr32Barrier(1, &cancelTimeout);
			[subscriber sendCompleted];
		}];
		
		return [RACDisposable disposableWithBlock:^{
			OSAtomicOr32Barrier(1, &cancelTimeout);
			[disposable dispose];
		}];
	}];
}

- (id<RACSignal>)deliverOn:(RACScheduler *)scheduler {
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		return [self subscribeNext:^(id x) {
			[scheduler schedule:^{
				[subscriber sendNext:x];
			}];
		} error:^(NSError *error) {
			[scheduler schedule:^{
				[subscriber sendError:error];
			}];
		} completed:^{
			[scheduler schedule:^{
				[subscriber sendCompleted];
			}];
		}];
	}];
}

- (id<RACSignal>)subscribeOn:(RACScheduler *)scheduler {
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		__block RACDisposable *innerDisposable = nil;
		[scheduler schedule:^{
			innerDisposable = [self subscribeNext:^(id x) {
				[subscriber sendNext:x];
			} error:^(NSError *error) {
				[subscriber sendError:error];
			} completed:^{
				[subscriber sendCompleted];
			}];
		}];
		
		return [RACDisposable disposableWithBlock:^{
			[innerDisposable dispose];
		}];
	}];
}

- (id<RACSignal>)let:(id<RACSignal> (^)(id<RACSignal> sharedSignal))letBlock {
	NSParameterAssert(letBlock != NULL);
	
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		RACConnectableSignal *connectable = [self publish];
		RACDisposable *finalDisposable = [letBlock(connectable) subscribeNext:^(id x) {
			[subscriber sendNext:x];
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			[subscriber sendCompleted];
		}];
		
		RACDisposable *connectableDisposable = [connectable connect];
		
		return [RACDisposable disposableWithBlock:^{
			[connectableDisposable dispose];
			[finalDisposable dispose];
		}];
	}];
}

- (id<RACSignal>)groupBy:(id<NSCopying> (^)(id object))keyBlock transform:(id (^)(id object))transformBlock {
	NSParameterAssert(keyBlock != NULL);

	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		NSMutableDictionary *groups = [NSMutableDictionary dictionary];

		return [self subscribeNext:^(id x) {
			id<NSCopying> key = keyBlock(x);
			RACGroupedSignal *groupSubject = nil;
			@synchronized(groups) {
				groupSubject = [groups objectForKey:key];
				if(groupSubject == nil) {
					groupSubject = [RACGroupedSignal signalWithKey:key];
					[groups setObject:groupSubject forKey:key];
					[subscriber sendNext:groupSubject];
				}
			}

			[groupSubject sendNext:transformBlock != NULL ? transformBlock(x) : x];
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			[subscriber sendCompleted];
		}];
	}];
}

- (id<RACSignal>)groupBy:(id<NSCopying> (^)(id object))keyBlock {
	return [self groupBy:keyBlock transform:nil];
}

- (id<RACSignal>)any {	
	return [self any:^(id x) {
		return YES;
	}];
}

- (id<RACSignal>)any:(BOOL (^)(id object))predicateBlock {
	NSParameterAssert(predicateBlock != NULL);
	
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		__block RACDisposable *disposable = [self subscribeNext:^(id x) {
			if(predicateBlock(x)) {
				[subscriber sendNext:@(YES)];
				[disposable dispose];
				[subscriber sendCompleted];
			}
		} error:^(NSError *error) {
			[subscriber sendNext:@(NO)];
			[subscriber sendError:error];
		} completed:^{
			[subscriber sendNext:@(NO)];
			[subscriber sendCompleted];
		}];
		
		return disposable;
	}];
}

- (id<RACSignal>)all:(BOOL (^)(id object))predicateBlock {
	NSParameterAssert(predicateBlock != NULL);
	
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		__block RACDisposable *disposable = [self subscribeNext:^(id x) {
			if(!predicateBlock(x)) {
				[subscriber sendNext:@(NO)];
				[disposable dispose];
				[subscriber sendCompleted];
			}
		} error:^(NSError *error) {
			[subscriber sendNext:@(NO)];
			[subscriber sendError:error];
		} completed:^{
			[subscriber sendNext:@(YES)];
			[subscriber sendCompleted];
		}];
		
		return disposable;
	}];
}

- (id<RACSignal>)retry:(NSInteger)retryCount {
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		__block NSInteger currentRetryCount = 0;
		
		__block RACDisposable *currentDisposable = nil;
		__block RACSubscriber *innerSubscriber = [RACSubscriber subscriberWithNext:^(id x) {
			[subscriber sendNext:x];
		} error:^(NSError *error) {
			if(retryCount == 0 || currentRetryCount < retryCount) {
				currentDisposable = [self subscribe:innerSubscriber];
			} else {
				[subscriber sendError:error];
			}
			
			currentRetryCount++;
		} completed:^{
			[subscriber sendCompleted];
		}];
		
		currentDisposable = [self subscribe:innerSubscriber];
		
		return [RACDisposable disposableWithBlock:^{
			[currentDisposable dispose];
		}];
	}];
}

- (id<RACSignal>)retry {
	return [self retry:0];
}

- (RACCancelableSignal *)asCancelableToSubject:(RACSubject *)subject withBlock:(void (^)(void))block {
	return [RACCancelableSignal cancelableSignalSourceSignal:self subject:subject withBlock:block];
}

- (RACCancelableSignal *)asCancelableWithBlock:(void (^)(void))block {
	return [RACCancelableSignal cancelableSignalSourceSignal:self withBlock:block];
}

- (RACCancelableSignal *)asCancelable {
	return [self asCancelableWithBlock:NULL];
}

@end
